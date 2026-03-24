fn main() {
    match sql_read_tools::run_from_env() {
        Ok(output) => {
            if !output.is_empty() {
                println!("{output}");
            }
        }
        Err(sql_read_tools::CliError::Help(text)) => {
            println!("{text}");
        }
        Err(sql_read_tools::CliError::Message(message)) => {
            eprintln!("{message}");
            std::process::exit(1);
        }
    }
}
