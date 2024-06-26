use std::fmt::Debug;
use std::num::NonZeroU64;

use async_trait::async_trait;

use crate::{
    traits::TxOutcome, utils::domain_hash, BatchItem, ChainCommunicationError, ChainResult,
    HyperlaneContract, HyperlaneMessage, TxCostEstimate, H256, U256,
};

/// Interface for the Mailbox chain contract. Allows abstraction over different
/// chains
#[async_trait]
pub trait Mailbox: HyperlaneContract + Send + Sync + Debug {
    /// Return the domain hash
    fn domain_hash(&self) -> H256 {
        domain_hash(self.address(), self.domain().id())
    }

    /// Gets the current leaf count of the merkle tree
    ///
    /// - `lag` is how far behind the current block to query, if not specified
    ///   it will query at the latest block.
    async fn count(&self, lag: Option<NonZeroU64>) -> ChainResult<u32>;

    /// Fetch the status of a message
    async fn delivered(&self, id: H256) -> ChainResult<bool>;

    /// Fetch the current default interchain security module value
    async fn default_ism(&self) -> ChainResult<H256>;

    /// Get the latest checkpoint.
    async fn recipient_ism(&self, recipient: H256) -> ChainResult<H256>;

    /// Process a message with a proof against the provided signed checkpoint
    async fn process(
        &self,
        message: &HyperlaneMessage,
        metadata: &[u8],
        tx_gas_limit: Option<U256>,
    ) -> ChainResult<TxOutcome>;

    /// Process a message with a proof against the provided signed checkpoint
    async fn process_batch(
        &self,
        _messages: &[BatchItem<HyperlaneMessage>],
    ) -> ChainResult<TxOutcome> {
        // Batching is not supported by default
        Err(ChainCommunicationError::BatchingFailed)
    }

    /// Estimate transaction costs to process a message.
    async fn process_estimate_costs(
        &self,
        message: &HyperlaneMessage,
        metadata: &[u8],
    ) -> ChainResult<TxCostEstimate>;

    /// Get the calldata for a transaction to process a message with a proof
    /// against the provided signed checkpoint
    fn process_calldata(&self, message: &HyperlaneMessage, metadata: &[u8]) -> Vec<u8>;
}
