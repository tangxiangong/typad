//! TyPad-owned worker. Private versioned JSON-lines IPC; no Tinymist CLI or LSP transport.
mod engine;
use serde::Deserialize;
use serde_json::json;
use std::io::{self, BufRead, Read, Write};

#[derive(Deserialize)]
struct Request {
    protocol: u32,
    id: u64,
    revision: u64,
    operation: String,
    source: String,
    path: Option<String>,
    #[serde(default)]
    offset: usize,
    #[serde(default)]
    root: Option<String>,
    #[serde(default)]
    files: std::collections::BTreeMap<String, String>,
}

fn main() {
    let mut engine = engine::Engine::default();
    let mut input = io::stdin().lock();
    let mut output = io::BufWriter::new(io::stdout().lock());
    loop {
        let mut frame = Vec::new();
        // Bound allocation even for malformed input without a newline.
        let read = input
            .by_ref()
            .take(16 * 1024 * 1024 + 1)
            .read_until(b'\n', &mut frame);
        match read {
            Ok(0) | Err(_) => break,
            _ => {}
        }
        if frame.len() > 16 * 1024 * 1024 {
            break;
        }
        let request: Request = match serde_json::from_slice(&frame) {
            Ok(value) => value,
            Err(_) => break,
        };
        let result = if request.protocol != 1 {
            Err("Unsupported protocol version".into())
        } else {
            engine.execute(&request)
        };
        let response = match result {
            Ok(value) => {
                json!({"protocol":1,"id":request.id,"revision":request.revision,"result":value})
            }
            Err(error) => {
                json!({"protocol":1,"id":request.id,"revision":request.revision,"error":error})
            }
        };
        if serde_json::to_writer(&mut output, &response).is_err()
            || output.write_all(b"\n").is_err()
            || output.flush().is_err()
        {
            break;
        }
    }
}
