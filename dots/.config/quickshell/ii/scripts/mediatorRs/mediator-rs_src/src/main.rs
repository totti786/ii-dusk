fn main() {
    // A closed pipe (`mediator list | head`) is not an error; Python exited 0 quietly
    let default = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let msg = info.payload().downcast_ref::<String>().map(String::as_str).or_else(|| info.payload().downcast_ref::<&str>().copied()).unwrap_or("");
        if !msg.contains("Broken pipe") {
            default(info);
        }
    }));
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match std::panic::catch_unwind(|| mediator::cli::main(args)) {
        Ok(c) => c,
        Err(p) => {
            let broken = p.downcast_ref::<String>().map(|s| s.contains("Broken pipe")).unwrap_or(false);
            if broken { 0 } else { 101 }
        }
    };
    std::process::exit(code);
}
