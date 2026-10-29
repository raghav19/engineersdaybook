//! A Lapce volt (plugin) that starts a language server. One build serves every language server of the sandbox.
//! Each server has its own folder with `volt.toml`. The `[server]` table of that file says which program to run.
//! Lapce gives the volt folder to the wasm module as `/`, so the module reads `/volt.toml`.
use anyhow::{Context, Result};
use lapce_plugin::{
    psp_types::{
        lsp_types::{request::Initialize, DocumentFilter, DocumentSelector, InitializeParams, MessageType, Url},
        Request,
    },
    register_plugin, LapcePlugin, PLUGIN_RPC,
};
use serde::Deserialize;
use serde_json::Value;

#[derive(Default)]
struct State {}

register_plugin!(State);

#[derive(Deserialize)]
struct Manifest {
    server: Server,
}

#[derive(Deserialize)]
struct Server {
    /// The program. Lapce looks it up in the PATH of the machine that runs lapce-proxy.
    command: String,
    #[serde(default)]
    args: Vec<String>,
    /// The language id of Lapce (python, yaml, ...). A file type without an id (Terraform, just) has none.
    language: Option<String>,
    /// The globs of the files of the server.
    patterns: Vec<String>,
}

fn initialize(params: InitializeParams) -> Result<()> {
    let text = std::fs::read_to_string("/volt.toml").context("cannot read /volt.toml")?;
    let Manifest { server } = toml::from_str(&text).context("cannot parse the [server] table of volt.toml")?;
    let selector: DocumentSelector = server
        .patterns
        .into_iter()
        .map(|pattern| DocumentFilter {
            language: server.language.clone(),
            pattern: Some(pattern),
            scheme: None,
        })
        .collect();
    // The settings of this volt in settings.toml reach the server as its initialization options.
    PLUGIN_RPC.start_lsp(
        Url::parse(&format!("urn:{}", server.command))?,
        server.args,
        selector,
        params.initialization_options,
    )?;
    Ok(())
}

impl LapcePlugin for State {
    fn handle_request(&mut self, _id: u64, method: String, params: Value) {
        if method == Initialize::METHOD {
            let result = serde_json::from_value(params).map_err(Into::into).and_then(initialize);
            if let Err(error) = result {
                // If Lapce cannot show the message, nothing else can report the error.
                let _ = PLUGIN_RPC.window_show_message(MessageType::ERROR, format!("lapce-lsp-launcher: {error:#}"));
            }
        }
    }
}
