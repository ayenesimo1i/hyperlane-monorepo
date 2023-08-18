use async_trait::async_trait;

use hyperlane_core::{
    ChainResult, ContractLocator, HyperlaneChain, HyperlaneContract, HyperlaneDomain,
    HyperlaneMessage, HyperlaneProvider, RawHyperlaneMessage, RoutingIsm, H256,
};

use crate::{
    grpc::{WasmGrpcProvider, WasmProvider},
    payloads::ism_routes::{IsmRouteRequest, IsmRouteRequestInner, IsmRouteRespnose},
    signers::Signer,
    verify::bech32_decode,
    ConnectionConf,
};

/// A reference to a RoutingIsm contract on some Cosmos chain
#[derive(Debug)]
pub struct CosmosRoutingIsm {
    _conf: ConnectionConf,
    domain: HyperlaneDomain,
    address: H256,
    _signer: Signer,
    provider: Box<WasmGrpcProvider>,
}

impl CosmosRoutingIsm {
    /// create a new instance of CosmosRoutingIsm
    pub fn new(conf: ConnectionConf, locator: ContractLocator, signer: Signer) -> Self {
        let provider = WasmGrpcProvider::new(conf.clone(), locator.clone(), signer.clone());

        Self {
            _conf: conf,
            domain: locator.domain.clone(),
            address: locator.address,
            _signer: signer,
            provider: Box::new(provider),
        }
    }
}

impl HyperlaneContract for CosmosRoutingIsm {
    fn address(&self) -> H256 {
        self.address
    }
}

impl HyperlaneChain for CosmosRoutingIsm {
    fn domain(&self) -> &HyperlaneDomain {
        &self.domain
    }

    fn provider(&self) -> Box<dyn HyperlaneProvider> {
        todo!()
    }
}

#[async_trait]
impl RoutingIsm for CosmosRoutingIsm {
    async fn route(&self, message: &HyperlaneMessage) -> ChainResult<H256> {
        let payload = IsmRouteRequest {
            route: IsmRouteRequestInner {
                message: hex::encode(RawHyperlaneMessage::from(message)),
            },
        };

        let data = self.provider.wasm_query(payload, None).await?;
        let response: IsmRouteRespnose = serde_json::from_slice(&data)?;

        Ok(bech32_decode(response.ism))
    }
}