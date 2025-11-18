#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use std::{
    fs,
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::Arc,
    time::Duration,
};
use tauri::{AppHandle, Manager, State, WindowEvent, Wry};
use tokio::{sync::Mutex, time::sleep};

struct BackendState {
    child: Arc<Mutex<Option<Child>>>,
}

#[derive(Deserialize)]
struct Handshake {
    port: u16,
}

#[tauri::command]
async fn shutdown_backend(state: State<'_, BackendState>) -> Result<(), String> {
    terminate_backend(Arc::clone(&state.child))
        .await
        .map_err(|err| err.to_string())
}

fn main() {
    tauri::Builder::default()
        .manage(BackendState {
            child: Arc::new(Mutex::new(None)),
        })
        .setup(|app| {
            let app_handle = app.handle();
            let state = Arc::clone(&app.state::<BackendState>().child);

            let window = tauri::WindowBuilder::new(
                app,
                "main",
                tauri::WindowUrl::App("index.html".into()),
            )
            .title("Hudson")
            .inner_size(1440.0, 900.0)
            .resizable(true)
            .build()?;

            eprintln!("Window created successfully");

            tauri::async_runtime::spawn(async move {
                if let Err(err) = boot_sequence(app_handle, state).await {
                    eprintln!("Backend boot failed: {err:?}");
                }
            });
            Ok(())
        })
        .on_window_event(|event| {
            if let WindowEvent::CloseRequested { .. } = event.event() {
                let state = Arc::clone(&event.window().state::<BackendState>().child);
                tauri::async_runtime::block_on(async move {
                    let _ = terminate_backend(state).await;
                });
            }
        })
        .invoke_handler(tauri::generate_handler![shutdown_backend])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

async fn boot_sequence(app: AppHandle<Wry>, state: Arc<Mutex<Option<Child>>>) -> Result<()> {
    eprintln!("Boot sequence started");

    let child = spawn_backend().context("failed to launch BEAM sidecar")?;
    eprintln!("Backend spawned");

    let port = wait_for_port_file().await?;
    eprintln!("Got port from handshake: {}", port);

    wait_for_health(port).await?;
    eprintln!("Health check passed");

    {
        let mut guard = state.lock().await;
        *guard = Some(child);
    }

    if let Some(window) = app.get_window("main") {
        eprintln!("Navigating window to http://127.0.0.1:{}", port);
        window
            .eval(&format!(
                "window.location.replace('http://127.0.0.1:{port}');"
            ))
            .context("failed to load LiveView into WebView")?;
        eprintln!("Navigation command sent");
    } else {
        return Err(anyhow!("Main window missing"));
    }

    Ok(())
}

fn spawn_backend() -> Result<Child> {
    let executable = std::env::var("HUDSON_BACKEND_BIN").unwrap_or_else(|_| default_backend_path());
    let args = std::env::var("HUDSON_BACKEND_ARGS")
        .map(|value| value.split_whitespace().map(String::from).collect())
        .unwrap_or_else(|_| default_args_for(&executable));

    let mut command = Command::new(executable);
    if !args.is_empty() {
        command.args(args);
    }

    command
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .context("failed to spawn backend process")
}

fn default_args_for(executable: &str) -> Vec<String> {
    if executable.contains("burrito_out") {
        vec![]
    } else {
        vec!["foreground".to_string()]
    }
}

fn default_backend_path() -> String {
    if cfg!(target_os = "windows") {
        let release = "..\\_build\\prod\\rel\\hudson\\bin\\hudson.bat".to_string();
        if std::path::Path::new(&release).exists() {
            release
        } else {
            "..\\burrito_out\\hudson_windows.exe".to_string()
        }
    } else {
        let release = "../_build/prod/rel/hudson/bin/hudson".to_string();
        if std::path::Path::new(&release).exists() {
            release
        } else if cfg!(target_arch = "aarch64") {
            "../burrito_out/hudson_macos_arm".to_string()
        } else {
            "../burrito_out/hudson_macos_intel".to_string()
        }
    }
}

async fn wait_for_port_file() -> Result<u16> {
    let path = handshake_path();
    for _ in 0..50 {
        if let Ok(contents) = fs::read_to_string(&path) {
            if let Ok(handshake) = serde_json::from_str::<Handshake>(&contents) {
                return Ok(handshake.port);
            }
        }
        sleep(Duration::from_millis(200)).await;
    }

    Err(anyhow!(
        "Timed out waiting for handshake file at {:?}",
        path
    ))
}

fn handshake_path() -> PathBuf {
    if cfg!(target_os = "macos") {
        PathBuf::from("/tmp/hudson_port.json")
    } else if cfg!(target_os = "windows") {
        let base =
            std::env::var("APPDATA").map(PathBuf::from).unwrap_or_else(|_| std::env::temp_dir());
        base.join("Hudson").join("port.json")
    } else {
        std::env::temp_dir().join("hudson_port.json")
    }
}

async fn wait_for_health(port: u16) -> Result<()> {
    let url = format!("http://127.0.0.1:{port}/healthz");
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(2))
        .build()?;

    for _ in 0..40 {
        if let Ok(response) = client.get(&url).send().await {
            if response.status().is_success() {
                return Ok(());
            }
        }
        sleep(Duration::from_millis(250)).await;
    }

    Err(anyhow!("Timed out waiting for /healthz on {url}"))
}

async fn terminate_backend(state: Arc<Mutex<Option<Child>>>) -> Result<()> {
    let mut guard = state.lock().await;
    if let Some(mut child) = guard.take() {
        let _ = child.kill();
        let _ = child.wait();
    }

    Ok(())
}
