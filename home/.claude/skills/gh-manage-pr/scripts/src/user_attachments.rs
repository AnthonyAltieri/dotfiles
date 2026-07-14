use crate::body::validate_attachment_url;
use crate::github::SecretToken;
use serde::Deserialize;
use std::fmt;
use std::time::Duration;
use ureq::http::header::CONTENT_TYPE;

const ENDPOINT: &str = "https://uploads.github.com/user-attachments/assets";
const MAX_RESPONSE_BYTES: u64 = 65_536;

pub struct UserAttachmentsClient {
    agent: ureq::Agent,
    endpoint: String,
}

impl UserAttachmentsClient {
    pub fn github() -> Self {
        Self::new(ENDPOINT, true)
    }

    fn new(endpoint: &str, https_only: bool) -> Self {
        let config = ureq::Agent::config_builder()
            .https_only(https_only)
            .max_redirects(0)
            .http_status_as_error(false)
            .timeout_connect(Some(Duration::from_secs(10)))
            .timeout_global(Some(Duration::from_secs(120)))
            .user_agent("gh-pr-image/0.1.0")
            .build();
        Self {
            agent: ureq::Agent::new_with_config(config),
            endpoint: endpoint.to_string(),
        }
    }

    #[cfg(test)]
    pub(crate) fn testing(endpoint: &str) -> Self {
        Self::new(endpoint, false)
    }

    pub fn upload(
        &self,
        repository_id: u64,
        name: &str,
        media_type: &str,
        bytes: &[u8],
        token: &SecretToken,
    ) -> Result<String, UploadError> {
        let authorization = format!("Bearer {}", token.expose());
        let repository_id = repository_id.to_string();
        let response = self
            .agent
            .post(&self.endpoint)
            .query_pairs([
                ("name", name),
                ("content_type", media_type),
                ("repository_id", repository_id.as_str()),
            ])
            .header("Authorization", authorization)
            .header("Accept", "application/json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .content_type("application/octet-stream")
            .send(bytes)
            .map_err(classify_send_error)?;

        let status = response.status().as_u16();
        if (400..500).contains(&status) {
            if !is_known_rejection_status(status) || !has_json_content_type(&response) {
                return Err(UploadError::Ambiguous("untrusted client-error response"));
            }
            let mut response = response;
            let body = read_bounded_body(&mut response)?;
            let rejection: RejectionResponse = serde_json::from_slice(&body)
                .map_err(|_| UploadError::Ambiguous("malformed client-error response"))?;
            if rejection.message.trim().is_empty()
                || rejection.message.chars().any(char::is_control)
            {
                return Err(UploadError::Ambiguous("malformed client-error response"));
            }
            return Err(UploadError::Rejected(status));
        }
        if status != 201 {
            return Err(UploadError::Ambiguous("unexpected HTTP status"));
        }
        if !has_json_content_type(&response) {
            return Err(UploadError::Ambiguous(
                "unexpected success response content type",
            ));
        }

        let mut response = response;
        let body = read_bounded_body(&mut response)?;
        let parsed: UploadResponse = serde_json::from_slice(&body)
            .map_err(|_| UploadError::Ambiguous("malformed success response"))?;
        let url = match (parsed.url, parsed.href) {
            (Some(url), Some(href)) if url == href => url,
            (Some(_), Some(_)) => {
                return Err(UploadError::Ambiguous("conflicting success response URLs"));
            }
            (Some(url), None) | (None, Some(url)) => url,
            (None, None) => return Err(UploadError::Ambiguous("missing success response URL")),
        };
        validate_attachment_url(&url)
            .map_err(|_| UploadError::Ambiguous("untrusted success response URL"))?;
        Ok(url)
    }
}

#[derive(Deserialize)]
struct UploadResponse {
    url: Option<String>,
    href: Option<String>,
}

#[derive(Deserialize)]
struct RejectionResponse {
    message: String,
}

fn read_bounded_body(
    response: &mut ureq::http::Response<ureq::Body>,
) -> Result<Vec<u8>, UploadError> {
    response
        .body_mut()
        .with_config()
        .limit(MAX_RESPONSE_BYTES)
        .read_to_vec()
        .map_err(|_| UploadError::Ambiguous("invalid or oversized response body"))
}

fn has_json_content_type(response: &ureq::http::Response<ureq::Body>) -> bool {
    response
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split(';').next())
        .is_some_and(|value| {
            matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "application/json" | "application/vnd.github+json"
            )
        })
}

fn is_known_rejection_status(status: u16) -> bool {
    matches!(status, 400 | 401 | 403 | 404 | 413 | 415 | 422)
}

fn classify_send_error(error: ureq::Error) -> UploadError {
    match error {
        ureq::Error::Http(_)
        | ureq::Error::BadUri(_)
        | ureq::Error::HostNotFound
        | ureq::Error::InvalidProxyUrl
        | ureq::Error::ConnectionFailed
        | ureq::Error::BodyExceedsLimit(_)
        | ureq::Error::Tls(_)
        | ureq::Error::RequireHttpsOnly(_)
        | ureq::Error::ConnectProxyFailed(_)
        | ureq::Error::TlsRequired => UploadError::NotSent("request failed before dispatch"),
        _ => UploadError::Ambiguous("transport failure during or after dispatch"),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UploadError {
    NotSent(&'static str),
    Rejected(u16),
    Ambiguous(&'static str),
}

impl UploadError {
    pub fn is_ambiguous(self) -> bool {
        matches!(self, Self::Ambiguous(_))
    }
}

impl fmt::Display for UploadError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotSent(category) => {
                write!(formatter, "Attachment upload was not sent ({category}).")
            }
            Self::Rejected(status) => write!(
                formatter,
                "GitHub rejected the attachment upload with HTTP {status}."
            ),
            Self::Ambiguous(category) => write!(
                formatter,
                "Attachment upload outcome is ambiguous ({category}); it was not retried and may have created an orphan attachment."
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::github::SecretToken;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::thread;

    #[test]
    fn sends_encoded_query_raw_bytes_and_secret_header() {
        let (endpoint, server) = server_once(
            201,
            r#"{"url":"https://github.com/user-attachments/assets/abc-123"}"#,
        );
        let client = UserAttachmentsClient::new(&endpoint, false);
        let token = SecretToken::new("secret-token".to_string()).expect("token");
        let url = client
            .upload(123, "screen shot.png", "image/png", b"exact-bytes", &token)
            .expect("upload");
        assert_eq!(url, "https://github.com/user-attachments/assets/abc-123");

        let request = server.join().expect("server");
        assert!(request.starts_with(
            "POST /user-attachments/assets?name=screen%20shot.png&content_type=image%2Fpng&repository_id=123 HTTP/1.1"
        ));
        let lowercase = request.to_ascii_lowercase();
        assert!(lowercase.contains("authorization: bearer secret-token"));
        assert!(lowercase.contains("accept: application/json"));
        assert!(lowercase.contains("x-github-api-version: 2022-11-28"));
        assert!(lowercase.contains("content-type: application/octet-stream"));
        assert!(lowercase.contains("content-length: 11"));
        assert!(lowercase.contains("user-agent: gh-pr-image/0.1.0"));
        assert!(request.ends_with("exact-bytes"));
    }

    #[test]
    fn classifies_server_and_malformed_success_failures_as_ambiguous() {
        for (status, body) in [(500, "{}"), (201, "not-json")] {
            let (endpoint, server) = server_once(status, body);
            let client = UserAttachmentsClient::new(&endpoint, false);
            let token = SecretToken::new("do-not-print".to_string()).expect("token");
            let error = client
                .upload(1, "a.png", "image/png", b"png", &token)
                .expect_err("ambiguous");
            assert!(error.is_ambiguous());
            assert!(!error.to_string().contains("do-not-print"));
            server.join().expect("server");
        }
    }

    #[test]
    fn classifies_client_rejection_without_echoing_body() {
        let (endpoint, server) = server_once(403, r#"{"message":"Forbidden"}"#);
        let client = UserAttachmentsClient::new(&endpoint, false);
        let token = SecretToken::new("secret-token".to_string()).expect("token");
        let error = client
            .upload(1, "a.png", "image/png", b"png", &token)
            .expect_err("rejected");
        assert_eq!(error, UploadError::Rejected(403));
        assert!(!error.to_string().contains("secret-token"));
        server.join().expect("server");
    }

    #[test]
    fn treats_uncertain_or_malformed_client_errors_as_ambiguous() {
        for (status, body) in [
            (408, r#"{"message":"Timeout"}"#),
            (425, r#"{"message":"Too Early"}"#),
            (499, r#"{"message":"Client Closed"}"#),
            (403, "not-json"),
        ] {
            let (endpoint, server) = server_once(status, body);
            let client = UserAttachmentsClient::new(&endpoint, false);
            let token = SecretToken::new("secret-token".to_string()).expect("token");
            let error = client
                .upload(1, "a.png", "image/png", b"png", &token)
                .expect_err("ambiguous client response");
            assert!(error.is_ambiguous(), "status {status}: {error}");
            server.join().expect("server");
        }
    }

    #[test]
    fn validates_success_url_variants_and_response_limit() {
        for (body, expected) in [
            (
                r#"{"href":"https://github.com/user-attachments/assets/href-only"}"#,
                true,
            ),
            (
                r#"{"url":"https://github.com/user-attachments/assets/same","href":"https://github.com/user-attachments/assets/same"}"#,
                true,
            ),
            (
                r#"{"url":"https://github.com/user-attachments/assets/one","href":"https://github.com/user-attachments/assets/two"}"#,
                false,
            ),
            (r#"{}"#, false),
            (r#"{"url":"https://evil.example/asset"}"#, false),
        ] {
            let (endpoint, server) = server_once(201, body);
            let client = UserAttachmentsClient::new(&endpoint, false);
            let token = SecretToken::new("secret-token".to_string()).expect("token");
            let result = client.upload(1, "a.png", "image/png", b"png", &token);
            assert_eq!(result.is_ok(), expected, "{body}");
            server.join().expect("server");
        }

        let oversized = "x".repeat(MAX_RESPONSE_BYTES as usize + 1);
        let (endpoint, server) = server_once(201, &oversized);
        let client = UserAttachmentsClient::new(&endpoint, false);
        let token = SecretToken::new("secret-token".to_string()).expect("token");
        let error = client
            .upload(1, "a.png", "image/png", b"png", &token)
            .expect_err("oversized response");
        assert!(error.is_ambiguous());
        server.join().expect("server");

        let (endpoint, server) = server_once_with_headers(
            201,
            r#"{"url":"https://github.com/user-attachments/assets/id"}"#,
            "text/plain",
            "",
        );
        let client = UserAttachmentsClient::new(&endpoint, false);
        let error = client
            .upload(1, "a.png", "image/png", b"png", &token)
            .expect_err("wrong content type");
        assert!(error.is_ambiguous());
        server.join().expect("server");
    }

    #[test]
    fn does_not_follow_redirects_and_identifies_local_request_errors() {
        let redirect_target = TcpListener::bind("127.0.0.1:0").expect("redirect target");
        redirect_target
            .set_nonblocking(true)
            .expect("nonblocking target");
        let location = format!(
            "Location: http://{}/elsewhere\r\n",
            redirect_target.local_addr().expect("target address")
        );
        let (endpoint, server) = server_once_with_headers(302, "", "application/json", &location);
        let client = UserAttachmentsClient::new(&endpoint, false);
        let token = SecretToken::new("secret-token".to_string()).expect("token");
        let error = client
            .upload(1, "a.png", "image/png", b"png", &token)
            .expect_err("redirect");
        assert!(error.is_ambiguous());
        server.join().expect("server");
        assert_eq!(
            redirect_target
                .accept()
                .expect_err("no redirected request")
                .kind(),
            std::io::ErrorKind::WouldBlock
        );

        let client = UserAttachmentsClient::new("not a URL", false);
        let error = client
            .upload(1, "a.png", "image/png", b"png", &token)
            .expect_err("local URI error");
        assert!(matches!(error, UploadError::NotSent(_)));
    }

    fn server_once(status: u16, body: &str) -> (String, thread::JoinHandle<String>) {
        server_once_with_headers(status, body, "application/json", "")
    }

    fn server_once_with_headers(
        status: u16,
        body: &str,
        content_type: &str,
        extra_headers: &str,
    ) -> (String, thread::JoinHandle<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("listen");
        let address = listener.local_addr().expect("address");
        let body = body.to_string();
        let content_type = content_type.to_string();
        let extra_headers = extra_headers.to_string();
        let handle = thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept");
            let mut bytes = Vec::new();
            let mut buffer = [0u8; 4096];
            loop {
                let count = stream.read(&mut buffer).expect("read");
                if count == 0 {
                    break;
                }
                bytes.extend_from_slice(&buffer[..count]);
                if let Some(header_end) = find_subslice(&bytes, b"\r\n\r\n") {
                    let headers = String::from_utf8_lossy(&bytes[..header_end]);
                    let content_length = headers
                        .lines()
                        .find_map(|line| {
                            line.to_ascii_lowercase()
                                .strip_prefix("content-length: ")
                                .and_then(|value| value.parse::<usize>().ok())
                        })
                        .unwrap_or(0);
                    if bytes.len() >= header_end + 4 + content_length {
                        break;
                    }
                }
            }
            let reason = if status == 201 { "Created" } else { "Error" };
            let response = format!(
                "HTTP/1.1 {status} {reason}\r\nContent-Type: {content_type}\r\n{extra_headers}Content-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            stream.write_all(response.as_bytes()).expect("respond");
            String::from_utf8(bytes).expect("request utf8")
        });
        (format!("http://{address}/user-attachments/assets"), handle)
    }

    fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
        haystack
            .windows(needle.len())
            .position(|window| window == needle)
    }
}
