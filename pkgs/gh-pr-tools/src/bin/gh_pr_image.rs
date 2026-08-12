use gh_manage_pr_tools::cli::{parse_args, ParsedArgs, HELP};
use gh_manage_pr_tools::github::GhClient;
use gh_manage_pr_tools::user_attachments::UserAttachmentsClient;
use gh_manage_pr_tools::{add_image_to_pr, ErrorKind};

fn main() {
    let parsed = match parse_args(std::env::args().skip(1).collect()) {
        Ok(parsed) => parsed,
        Err(error) => {
            eprintln!("{error}\n\n{HELP}");
            std::process::exit(2);
        }
    };

    let ParsedArgs::Add(config) = parsed else {
        println!("{HELP}");
        return;
    };

    let github = GhClient::new("gh");
    let uploader = UserAttachmentsClient::github();
    match add_image_to_pr(&config, &github, &uploader) {
        Ok(output) => {
            if let Some(warning) = output.warning {
                eprintln!("warning: {warning}");
            }
            println!("{}", output.pull_request_url);
            println!("{}", output.markdown);
        }
        Err(error) => {
            eprintln!("{error}");
            let code = match error.kind() {
                ErrorKind::Usage => 2,
                ErrorKind::Runtime => 1,
            };
            std::process::exit(code);
        }
    }
}
