const std = @import("std");
const types = @import("types.zig");

pub const UINT64_MAX: u64 = std.math.maxInt(u64);
pub const UINT64_MAX_SQRT: u64 = 4294967295;
pub const GENESIS_SLOT: types.Slot = 0;
pub const GENESIS_EPOCH: types.Epoch = 0;
pub const FAR_FUTURE_EPOCH: types.Epoch = std.math.maxInt(u64);
pub const BASE_REWARDS_PER_EPOCH: u64 = 4;
pub const DEPOSIT_CONTRACT_TREE_DEPTH: u64 = 32;
pub const JUSTIFICATION_BITS_LENGTH: u64 = 4;
pub const ENDIANNESS = .little;
pub const BLS_WITHDRAWAL_PREFIX: types.Bytes1 = .{0x00};
pub const ETH1_ADDRESS_WITHDRAWAL_PREFIX: types.Bytes1 = .{0x01};
pub const DOMAIN_BEACON_PROPOSER: types.DomainType = .{ 0x00, 0x00, 0x00, 0x00 };
pub const DOMAIN_BEACON_ATTESTER: types.DomainType = .{ 0x01, 0x00, 0x00, 0x00 };
pub const DOMAIN_RANDAO: types.DomainType = .{ 0x02, 0x00, 0x00, 0x00 };
pub const DOMAIN_DEPOSIT: types.DomainType = .{ 0x03, 0x00, 0x00, 0x00 };
pub const DOMAIN_VOLUNTARY_EXIT: types.DomainType = .{ 0x04, 0x00, 0x00, 0x00 };
pub const DOMAIN_SELECTION_PROOF: types.DomainType = .{ 0x05, 0x00, 0x00, 0x00 };
pub const DOMAIN_AGGREGATE_AND_PROOF: types.DomainType = .{ 0x06, 0x00, 0x00, 0x00 };
pub const DOMAIN_APPLICATION_MASK: types.DomainType = .{ 0x00, 0x00, 0x00, 0x01 };
pub const INTERVALS_PER_SLOT: u64 = 3;
pub const NODE_ID_BITS: u64 = 256;
pub const TARGET_AGGREGATORS_PER_COMMITTEE: u64 = std.math.pow(u64, 2, 4);
pub const ETH_TO_GWEI: u64 = std.math.pow(u64, 10, 9);
pub const SAFETY_DECAY: u64 = 10;

pub const EXECUTION_PAYLOAD_GINDEX: usize = 25;
pub const FINALIZED_ROOT_GINDEX_ELECTRA: usize = 169;
