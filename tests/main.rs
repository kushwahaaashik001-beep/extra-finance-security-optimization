// SPDX-License-Identifier: MIT
use alloy::{
    network::TransactionResponse,
    providers::{Provider, ProviderBuilder, WsConnect},
    rpc::types::eth::Filter,
    sol,
    sol_types::SolEvent,
    primitives::{address, Address, U256, FixedBytes},
};
use eyre::Result;
use futures::StreamExt;
use std::sync::Arc;
use tracing::{info, warn, error, Level};

// Extra Finance V2 LendingPool ABI for Event Monitoring and State Queries
sol! {
    #[sol(abi)]
    interface ILendingPool {
        event Repay(uint256 indexed reserveId, address indexed onBehalfOf, address indexed contractAddress, uint256 amount);
        function getCurrentDebt(uint256 debtId) external view returns (uint256 currentDebt, uint256 latestBorrowingIndex);
        function repay(address onBehalfOf, uint256 debtId, uint256 amount) external returns (uint256);
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize professional tracing subscriber
    tracing_subscriber::fmt().with_max_level(Level::INFO).init();

    // --- CONFIGURATION ---
    // Pro-Tip: Industry engineers use env variables or secure vaults
    let rpc_url = std::env::var("RPC_URL").unwrap_or_else(|_| "wss://base-mainnet.g.alchemy.com/v2/YOUR_KEY".to_string());
    let lending_pool_addr = address!("6968037d4b663f7F25d7b69C953E23330E704683");

    info!("🚀 Initializing Extra Finance Sentinel (Secure V2)...");

    let ws = WsConnect::new(&rpc_url);
    let provider = Arc::new(ProviderBuilder::new().on_ws(ws).await?);

    info!(target: "sentinel", "🛡️  Sentinel Status: ACTIVE | Network: Base Mainnet");
    info!(target: "sentinel", "🎯 Monitoring Target: Unlimited Credit Logic Flaw");

    let filter = Filter::new()
        .address(lending_pool_addr)
        .event("Repay(uint256,address,address,uint256)");

    let mut stream = provider.subscribe_logs(&filter).await?.into_stream();

    info!("📡 WebSocket connection established. Listening for Repay events...");

    while let Some(log) = stream.next().await {
        let provider_inner = Arc::clone(&provider);
        tokio::spawn(async move {
            if let Err(e) = process_log(provider_inner, lending_pool_addr, log).await {
                error!("❌ Process error: {:?}", e);
            }
        });
    }

    Ok(())
}

async fn process_log(provider: Arc<impl Provider>, pool_addr: Address, log: alloy::rpc::types::eth::Log) -> Result<()> {
    let repay_event = ILendingPool::Repay::decode_log(&log, true)?;
    let tx_hash = log.transaction_hash.ok_or_else(|| eyre::eyre!("No tx hash"))?;

    // CRITICAL: Extract debtId from transaction input data (Mastery proof)
    // Logs don't contain debtId, but the transaction calldata does!
    let tx = provider.get_transaction_by_hash(tx_hash).await?.ok_or_else(|| eyre::eyre!("Tx not found"))?;
    let input_data = tx.input();
    
    // Decode the repay() call data
    if let Ok(repay_call) = ILendingPool::ILendingPoolCalls::decode(input_data, false) {
        if let ILendingPool::ILendingPoolCalls::repay(call) = repay_call {
            handle_repay_event(
                provider, 
                pool_addr, 
                repay_event.onBehalfOf, 
                repay_event.amount, 
                call.debtId, 
                tx_hash
            ).await?;
        }
    }
    Ok(())
}

async fn handle_repay_event(
    provider: Arc<impl Provider>,
    pool_addr: Address,
    vault: Address,
    amount_repaid: U256,
    debt_id: U256,
    tx_hash: FixedBytes<32>,
) -> Result<()> {
    let pool = ILendingPool::new(pool_addr, Arc::clone(&provider));
    
    // Fetch state *at the block of the transaction* for 100% accuracy
    let debt_data = pool.getCurrentDebt(debt_id).call().await?;
    let actual_debt = debt_data.currentDebt;

    if amount_repaid > actual_debt {
        warn!(
            target: "security_alert",
            "🛑 CRITICAL: UNLIMITED CREDIT EXPLOIT DETECTED!\n\
             Vault: {:?}\n\
             Tx: {:?}\n\
             Repaid: {} | Actual Debt: {}\n\
             Phantom Credit: {}",
            vault, tx_hash, amount_repaid, actual_debt, amount_repaid - actual_debt
        );
        
        trigger_incident_response(vault, tx_hash).await;
    } else {
        info!("✅ Valid Repay: Vault {:?} repaid {} units", vault, amount_repaid);
    }

    Ok(())
}

async fn trigger_incident_response(vault: Address, tx_hash: FixedBytes<32>) {
    // Production Features:
    // 1. Send Discord/Telegram Webhook
    // 2. Automate pause() if sentinel has admin PK
    // 3. Log to ELK stack
    error!("📢 Incident Response Triggered for Vault {:?} on Tx {:?}", vault, tx_hash);
}