// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! A minimal binary for testing `dist` releases.
//!
//! It has no dependencies so that release builds stay fast. The `completion`
//! subcommand exists because the Homebrew formula that `dist` generates calls
//! it to install shell completions, as it does for the Oxide CLI. Like the
//! Oxide CLI, it takes the shell as `-s` or `--shell`, which is the form that
//! the formula's `shell_parameter_format: :arg` passes: `--shell=bash`.

use std::process::ExitCode;

const NAME: &str = env!("CARGO_PKG_NAME");
const VERSION: &str = env!("CARGO_PKG_VERSION");

const BASH_COMPLETION: &str = "complete -W 'completion --help --version' dist-test\n";

const ZSH_COMPLETION: &str = "\
#compdef dist-test
_arguments \\
  '--help[Print help]' \\
  '--version[Print version]' \\
  '1:command:(completion)' \\
  '(-s --shell)'{-s,--shell}'[Shell type]:shell:(bash fish zsh)'
";

const FISH_COMPLETION: &str = "\
complete -c dist-test -l help -d 'Print help'
complete -c dist-test -l version -d 'Print version'
complete -c dist-test -n __fish_use_subcommand -a completion -d 'Print a shell completion script'
complete -c dist-test -n '__fish_seen_subcommand_from completion' -s s -l shell -x -a 'bash fish zsh' -d 'Shell type'
";

fn usage() -> String {
    format!(
        "Usage: {NAME} [--help | --version]\n       {NAME} completion --shell <bash|fish|zsh>\n"
    )
}

/// Returns the shell named by the arguments after `completion`, accepting the
/// same forms as clap: `-s SHELL`, `--shell SHELL`, and `--shell=SHELL`.
fn completion_shell<'a>(args: &[&'a str]) -> Option<&'a str> {
    match args {
        ["-s" | "--shell", shell] => Some(shell),
        [arg] => arg.strip_prefix("--shell="),
        _ => None,
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();

    match args.as_slice() {
        [] | ["--help"] => {
            print!("{}", usage());
            ExitCode::SUCCESS
        }
        ["--version"] => {
            println!("{NAME} {VERSION}");
            ExitCode::SUCCESS
        }
        ["completion", rest @ ..] => {
            let Some(shell) = completion_shell(rest) else {
                eprint!("{}", usage());
                return ExitCode::FAILURE;
            };
            let script = match shell {
                "bash" => BASH_COMPLETION,
                "fish" => FISH_COMPLETION,
                "zsh" => ZSH_COMPLETION,
                _ => {
                    eprintln!("{NAME}: unsupported shell: {shell}");
                    return ExitCode::FAILURE;
                }
            };
            print!("{script}");
            ExitCode::SUCCESS
        }
        _ => {
            eprint!("{}", usage());
            ExitCode::FAILURE
        }
    }
}
