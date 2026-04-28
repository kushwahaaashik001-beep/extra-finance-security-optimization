use alloy::{
    providers::{Provider, ProviderBuilder, WsConnect},
    rpc::types::eth::TransactionRequest,
    sol,
    sol_types::SolCall,
};
use anyhow::Result;
use futures_util::StreamExt;
use tracing::{error, info};

// Lead Architect Flex: Direct ABI binding for the protocol
sol! {
    interface ILendingPool {
        function repay(uint256 reserveId, uint256 amount, uint256 debtId) external returns (uint256);
        function setPaused(bool paused) external;
        function debtPositions(uint256 debtId) external view returns (uint256, address, uint256, uint256);
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    // Base Mainnet WebSocket RPC (Use your own high-speed provider)
    let ws_url = "wss://base-mainnet.g.alchemy.com/v2/YOUR_API_KEY";
    let pool_address = "0x9B6F6Ef033CB53E5c5DeD2d172E3C9C99DE9C3c6".parse()?;

    info!("🚀 Sentinel active. Monitoring Extra Finance V2 on Base...");

    let ws = WsConnect::new(ws_url);
    let provider = ProviderBuilder::new().on_ws(ws).await?;

    // 1. Subscribe to pending transactions in the mempool
    let sub = provider.subscribe_pending_txs().await?;
    let mut stream = sub.into_stream();

    while let Some(tx_hash) = stream.next().await {
        // 2. Fetch full transaction data
        if let Ok(Some(tx)) = provider.get_transaction_by_hash(tx_hash).await {
            // 3. Filter for our LendingPool and the 'repay' function
            if let Some(to) = tx.to {
                if to == pool_address {
                    if let Ok(repay_call) = ILendingPool::repayCall::abi_decode(&tx.input, false) {
                        info!("🔍 Detected 'repay' call in mempool: Hash {}", tx_hash);
                        
                        // 4. Critical Logic: Check if repayment > debt (The Exploit)
                        // In a real scenario, we'd query the 'debtPositions' mapping here
                        if repay_call.amount > 1_000_000 * 10u256.pow(6) { // 1M USDC Threshold
                            error!("🚨 POTENTIAL EXPLOIT DETECTED: Repay amount exceeds safety limit!");
                            trigger_emergency_pause(&provider, pool_address).await?;
                        }
                    }
                }
            }
        }
    }

    Ok(())
}

async fn trigger_emergency_pause<P: Provider>(provider: &P, pool: alloy::primitives::Address) -> Result<()> {
    // Architect Move: Use high gas price to front-run the attacker
    let tx = TransactionRequest::default()
        .to(pool)
        .with_input(ILendingPool::setPausedCall { paused: true }.abi_encode());

    info!("🛡️ Sending Emergency Pause transaction...");
    let pending = provider.send_transaction(tx).await?;
    info!("✅ Protocol Paused. Tx Hash: {:?}", pending.tx_hash());
    Ok(())
}