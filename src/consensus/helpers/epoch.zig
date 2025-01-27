const std = @import("std");
const primitives = @import("../../primitives/types.zig");
const consensus = @import("../../consensus/types.zig");
const configs = @import("../../configs/config.zig");
const constants = @import("../../primitives/constants.zig");
const preset = @import("../../presets/preset.zig");
const phase0 = @import("../../consensus/phase0/types.zig");
const altair = @import("../../consensus/altair/types.zig");
const electra = @import("../../consensus/electra/types.zig");
const validator_helper = @import("../../consensus/helpers/validator.zig");

/// getCurrentEpoch returns the current epoch for the given state.
/// @return The current epoch.
/// Spec pseudocode definition:
/// def get_current_epoch(state: BeaconState) -> Epoch:
/// """
/// Return the current epoch.
/// """
/// return compute_epoch_at_slot(state.slot)
pub fn getCurrentEpoch(state: *const consensus.BeaconState) primitives.Epoch {
    return computeEpochAtSlot(state.slot());
}

/// Return the epoch number at `slot`.
/// @param slot - The slot number.
/// @return The epoch number.
/// @note This function is equivalent to `slot // SLOTS_PER_EPOCH`.
/// Spec pseudocode definition:
///
/// def compute_epoch_at_slot(slot: Slot) -> Epoch:
///    """
///    Return the epoch number at ``slot``.
///    """
///    return Epoch(slot // SLOTS_PER_EPOCH)
pub fn computeEpochAtSlot(slot: primitives.Slot) primitives.Epoch {
    // Return the epoch number at `slot`.
    return @divFloor(slot, preset.ActivePreset.get().SLOTS_PER_EPOCH);
}

/// getPreviousEpoch returns the previous epoch for the given state.
/// @param state - The state.
/// @return The previous epoch.
/// Spec pseudocode definition:
/// def get_previous_epoch(state: BeaconState) -> Epoch:
///    """
///    Return the previous epoch (unless the current epoch is ``GENESIS_EPOCH``).
///    """
///    current_epoch = get_current_epoch(state)
///    return GENESIS_EPOCH if current_epoch == GENESIS_EPOCH else Epoch(current_epoch - 1)
pub fn getPreviousEpoch(state: *const consensus.BeaconState) primitives.Epoch {
    // Return the previous epoch (unless the current epoch is `GENESIS_EPOCH`).
    const current_epoch = getCurrentEpoch(state);
    return if (current_epoch == constants.GENESIS_EPOCH) constants.GENESIS_EPOCH else @as(primitives.Epoch, current_epoch - 1);
}

//// computeStartSlotAtEpoch returns the start slot of `epoch`.
/// @param epoch - The epoch.
/// @return The start slot of `epoch`.
/// Spec pseudocode definition:
/// def compute_start_slot_at_epoch(epoch: Epoch) -> Slot:
///    """
///    Return the start slot of ``epoch``.
///    """
///    return Slot(epoch * SLOTS_PER_EPOCH)
pub fn computeStartSlotAtEpoch(epoch: primitives.Epoch) primitives.Slot {
    // Return the start slot of `epoch`.
    return @as(primitives.Slot, epoch * preset.ActivePreset.get().SLOTS_PER_EPOCH);
}

/// computeActivationExitEpoch returns the activation exit epoch for the given epoch.
/// @param epoch - The epoch.
/// @return The activation exit epoch for the given epoch.
/// Spec pseudocode definition:
/// def compute_activation_exit_epoch(epoch: Epoch) -> Epoch:
///     """
///     Return the epoch during which validator activations and exits initiated in ``epoch`` take effect.
///     """
///     return Epoch(epoch + 1 + MAX_SEED_LOOKAHEAD)
pub fn computeActivationExitEpoch(epoch: primitives.Epoch) primitives.Epoch {
    return @as(primitives.Epoch, epoch + 1 + preset.ActivePreset.get().MAX_SEED_LOOKAHEAD);
}

/// computeExitEpochAndUpdateChurn computes the exit epoch and updates the churn for the given state.
/// @param state - The state.
/// @param exit_balance - The exit balance.
/// @param allocator - The allocator.
/// @return The exit epoch and the updated churn.
/// Spec pseudocode definition:
/// def compute_exit_epoch_and_update_churn(state: BeaconState, exit_balance: Gwei) -> Epoch:
///     earliest_exit_epoch = max(state.earliest_exit_epoch, compute_activation_exit_epoch(get_current_epoch(state)))
///     per_epoch_churn = get_activation_exit_churn_limit(state)
///     # New epoch for exits.
///     if state.earliest_exit_epoch < earliest_exit_epoch:
///         exit_balance_to_consume = per_epoch_churn
///     else:
///        exit_balance_to_consume = state.exit_balance_to_consume
///
///    # Exit doesn't fit in the current earliest epoch.
///    if exit_balance > exit_balance_to_consume:
///        balance_to_process = exit_balance - exit_balance_to_consume
///        additional_epochs = (balance_to_process - 1) // per_epoch_churn + 1
///        earliest_exit_epoch += additional_epochs
///        exit_balance_to_consume += additional_epochs * per_epoch_churn
///
///   # Consume the balance and update state variables.
///   state.exit_balance_to_consume = exit_balance_to_consume - exit_balance
///   state.earliest_exit_epoch = earliest_exit_epoch
///
///   return state.earliest_exit_epoch
pub fn computeExitEpochAndUpdateChurn(state: *consensus.BeaconState, exit_balance: primitives.Gwei, allocator: std.mem.Allocator) !primitives.Epoch {
    var earliest_exit_epoch = @max(state.electra.earliest_exit_epoch, computeActivationExitEpoch(getCurrentEpoch(state)));
    const per_epoch_churn = try getActivationExitChurnLimit(state, allocator);
    var exit_balance_to_consume: primitives.Gwei = undefined;

    // New epoch for exits.
    if (state.electra.earliest_exit_epoch < earliest_exit_epoch) {
        exit_balance_to_consume = per_epoch_churn;
    } else {
        exit_balance_to_consume = state.electra.exit_balance_to_consume;
    }

    // Exit doesn't fit in the current earliest epoch.
    if (exit_balance > exit_balance_to_consume) {
        const balance_to_process = exit_balance - exit_balance_to_consume;
        const additional_epochs = @divFloor((balance_to_process - 1), per_epoch_churn) + 1;
        earliest_exit_epoch += additional_epochs;
        exit_balance_to_consume += additional_epochs * per_epoch_churn;
    }

    // Consume the balance and update state variables.
    state.electra.exit_balance_to_consume = exit_balance_to_consume - exit_balance;
    state.electra.earliest_exit_epoch = earliest_exit_epoch;

    return state.electra.earliest_exit_epoch;
}

/// getActivationExitChurnLimit returns the churn limit for the current epoch dedicated to activations and exits.
/// @param state - The state.
/// @param allocator - The allocator.
/// @return The churn limit for the current epoch dedicated to activations and exits.
/// Spec pseudocode definition:
/// def get_activation_exit_churn_limit(state: BeaconState) -> Gwei:
///     """
///     Return the churn limit for the current epoch dedicated to activations and exits.
///     """
///     return min(config.MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT, get_balance_churn_limit(state))
pub fn getActivationExitChurnLimit(state: *const consensus.BeaconState, allocator: std.mem.Allocator) !primitives.Gwei {
    const balance_churn_limit = try validator_helper.getBalanceChurnLimit(state, allocator);
    // Return the churn limit for the current epoch dedicated to activations and exits.
    return @min(configs.ActiveConfig.get().MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT, balance_churn_limit);
}

test "test compute_exit_epoch_and_update_churn" {
    preset.ActivePreset.set(preset.Presets.minimal);
    defer preset.ActivePreset.reset();
    configs.ActiveConfig.set(preset.Presets.minimal);
    defer configs.ActiveConfig.reset();
    var validators = std.ArrayList(consensus.Validator).init(std.testing.allocator);
    defer validators.deinit();
    const validator1 = consensus.Validator{
        .pubkey = undefined,
        .withdrawal_credentials = undefined,
        .effective_balance = 10000000000000,
        .slashed = false,
        .activation_eligibility_epoch = 0,
        .activation_epoch = 0,
        .exit_epoch = 10,
        .withdrawable_epoch = 10,
    };
    const validator2 = consensus.Validator{
        .pubkey = undefined,
        .withdrawal_credentials = undefined,
        .effective_balance = 10000000000000,
        .slashed = false,
        .activation_eligibility_epoch = 0,
        .activation_epoch = 0,
        .exit_epoch = 20,
        .withdrawable_epoch = 20,
    };
    try validators.append(validator1);
    try validators.append(validator2);
    var state = consensus.BeaconState{
        .electra = electra.BeaconState{
            .genesis_time = 0,
            .genesis_validators_root = .{0} ** 32,
            .slot = 0,
            .fork = undefined,
            .block_roots = undefined,
            .state_roots = undefined,
            .historical_roots = undefined,
            .eth1_data = undefined,
            .eth1_data_votes = undefined,
            .eth1_deposit_index = 0,
            .validators = validators.items,
            .balances = undefined,
            .randao_mixes = undefined,
            .slashings = undefined,
            .previous_epoch_attestations = undefined,
            .current_epoch_attestations = undefined,
            .justification_bits = undefined,
            .previous_justified_checkpoint = undefined,
            .current_justified_checkpoint = undefined,
            .finalized_checkpoint = undefined,
            .latest_block_header = undefined,
            .inactivity_scores = undefined,
            .current_sync_committee = undefined,
            .next_sync_committee = undefined,
            .earliest_exit_epoch = 5,
            .exit_balance_to_consume = 10000000000000,
            .latest_execution_payload_header = undefined,
            .historical_summaries = undefined,
            .pending_balance_deposits = undefined,
            .pending_partial_withdrawals = undefined,
            .pending_consolidations = undefined,
            .previous_epoch_participation = undefined,
            .current_epoch_participation = undefined,
        },
    };

    const exit_epoch = try computeExitEpochAndUpdateChurn(&state, 10000000000000, std.testing.allocator);
    try std.testing.expectEqual(5, exit_epoch);
}

test "test get_activation_exit_churn_limit" {
    preset.ActivePreset.set(preset.Presets.minimal);
    defer preset.ActivePreset.reset();
    configs.ActiveConfig.set(preset.Presets.minimal);
    defer configs.ActiveConfig.reset();
    var validators = std.ArrayList(consensus.Validator).init(std.testing.allocator);
    defer validators.deinit();
    const validator1 = consensus.Validator{
        .pubkey = undefined,
        .withdrawal_credentials = undefined,
        .effective_balance = 10000000000000,
        .slashed = false,
        .activation_eligibility_epoch = 0,
        .activation_epoch = 0,
        .exit_epoch = 10,
        .withdrawable_epoch = 10,
    };
    const validator2 = consensus.Validator{
        .pubkey = undefined,
        .withdrawal_credentials = undefined,
        .effective_balance = 10000000000000,
        .slashed = false,
        .activation_eligibility_epoch = 0,
        .activation_epoch = 0,
        .exit_epoch = 20,
        .withdrawable_epoch = 20,
    };
    try validators.append(validator1);
    try validators.append(validator2);
    var state = consensus.BeaconState{
        .altair = altair.BeaconState{
            .genesis_time = 0,
            .genesis_validators_root = .{0} ** 32,
            .slot = 0,
            .fork = undefined,
            .block_roots = undefined,
            .state_roots = undefined,
            .historical_roots = undefined,
            .eth1_data = undefined,
            .eth1_data_votes = undefined,
            .eth1_deposit_index = 0,
            .validators = validators.items,
            .balances = undefined,
            .randao_mixes = undefined,
            .slashings = undefined,
            .previous_epoch_attestations = undefined,
            .current_epoch_attestations = undefined,
            .justification_bits = undefined,
            .previous_justified_checkpoint = undefined,
            .current_justified_checkpoint = undefined,
            .finalized_checkpoint = undefined,
            .latest_block_header = undefined,
            .inactivity_scores = undefined,
            .current_sync_committee = undefined,
            .next_sync_committee = undefined,
            .previous_epoch_participation = undefined,
            .current_epoch_participation = undefined,
        },
    };
    const churn_limit = try getActivationExitChurnLimit(&state, std.testing.allocator);
    try std.testing.expectEqual(128000000000, churn_limit);
}

test "test compute_epoch_at_slot" {
    preset.ActivePreset.set(preset.Presets.mainnet);
    defer preset.ActivePreset.reset();
    const epoch = computeEpochAtSlot(0);
    try std.testing.expectEqual(0, epoch);

    const epoch2 = computeEpochAtSlot(1);
    try std.testing.expectEqual(0, epoch2);

    const epoch3 = computeEpochAtSlot(10);
    try std.testing.expectEqual(0, epoch3);

    const epoch4 = computeEpochAtSlot(100);
    try std.testing.expectEqual(3, epoch4);
}

test "test compute_start_slot_at_epoch" {
    preset.ActivePreset.set(preset.Presets.mainnet);
    defer preset.ActivePreset.reset();
    const slot = computeStartSlotAtEpoch(0);
    try std.testing.expectEqual(0, slot);

    const slot2 = computeStartSlotAtEpoch(1);
    try std.testing.expectEqual(32, slot2);

    const slot3 = computeStartSlotAtEpoch(2);
    try std.testing.expectEqual(64, slot3);

    const slot4 = computeStartSlotAtEpoch(3);
    try std.testing.expectEqual(96, slot4);
}

test "test get_current_epoch" {
    preset.ActivePreset.set(preset.Presets.mainnet);
    defer preset.ActivePreset.reset();

    const finalized_checkpoint = consensus.Checkpoint{
        .epoch = 5,
        .root = .{0} ** 32,
    };

    var validators = std.ArrayList(consensus.Validator).init(std.testing.allocator);
    defer validators.deinit();

    const validator1 = consensus.Validator{
        .pubkey = undefined,
        .withdrawal_credentials = undefined,
        .effective_balance = 0,
        .slashed = false,
        .activation_eligibility_epoch = 0,
        .activation_epoch = 0,
        .exit_epoch = 10,
        .withdrawable_epoch = 10,
    };

    const validator2 = consensus.Validator{
        .pubkey = undefined,
        .withdrawal_credentials = undefined,
        .effective_balance = 0,
        .slashed = false,
        .activation_eligibility_epoch = 0,
        .activation_epoch = 0,
        .exit_epoch = 20,
        .withdrawable_epoch = 20,
    };

    try validators.append(validator1);
    try validators.append(validator2);
    const state = consensus.BeaconState{
        .altair = altair.BeaconState{
            .genesis_time = 0,
            .genesis_validators_root = .{0} ** 32,
            .slot = 0,
            .fork = undefined,
            .block_roots = undefined,
            .state_roots = undefined,
            .historical_roots = undefined,
            .eth1_data = undefined,
            .eth1_data_votes = undefined,
            .eth1_deposit_index = 0,
            .validators = validators.items,
            .balances = undefined,
            .randao_mixes = undefined,
            .slashings = undefined,
            .previous_epoch_attestations = undefined,
            .current_epoch_attestations = undefined,
            .justification_bits = undefined,
            .previous_justified_checkpoint = undefined,
            .current_justified_checkpoint = undefined,
            .finalized_checkpoint = finalized_checkpoint,
            .latest_block_header = undefined,
            .inactivity_scores = undefined,
            .current_sync_committee = undefined,
            .next_sync_committee = undefined,
            .previous_epoch_participation = undefined,
            .current_epoch_participation = undefined,
        },
    };

    const epoch = getCurrentEpoch(&state);
    try std.testing.expectEqual(0, epoch);
}

test "test get_previous_epoch" {
    preset.ActivePreset.set(preset.Presets.mainnet);
    defer preset.ActivePreset.reset();
    const finalized_checkpoint = consensus.Checkpoint{
        .epoch = 5,
        .root = .{0} ** 32,
    };
    var validators = std.ArrayList(consensus.Validator).init(std.testing.allocator);
    defer validators.deinit();
    const validator1 = consensus.Validator{
        .pubkey = undefined,
        .withdrawal_credentials = undefined,
        .effective_balance = 0,
        .slashed = false,
        .activation_eligibility_epoch = 0,
        .activation_epoch = 0,
        .exit_epoch = 10,
        .withdrawable_epoch = 10,
    };
    const validator2 = consensus.Validator{
        .pubkey = undefined,
        .withdrawal_credentials = undefined,
        .effective_balance = 0,
        .slashed = false,
        .activation_eligibility_epoch = 0,
        .activation_epoch = 0,
        .exit_epoch = 20,
        .withdrawable_epoch = 20,
    };
    try validators.append(validator1);
    try validators.append(validator2);
    const state = consensus.BeaconState{
        .altair = altair.BeaconState{
            .genesis_time = 0,
            .genesis_validators_root = .{0} ** 32,
            .slot = 0,
            .fork = undefined,
            .block_roots = undefined,
            .state_roots = undefined,
            .historical_roots = undefined,
            .eth1_data = undefined,
            .eth1_data_votes = undefined,
            .eth1_deposit_index = 0,
            .validators = validators.items,
            .balances = undefined,
            .randao_mixes = undefined,
            .slashings = undefined,
            .previous_epoch_attestations = undefined,
            .current_epoch_attestations = undefined,
            .justification_bits = undefined,
            .previous_justified_checkpoint = undefined,
            .current_justified_checkpoint = undefined,
            .finalized_checkpoint = finalized_checkpoint,
            .latest_block_header = undefined,
            .inactivity_scores = undefined,
            .current_sync_committee = undefined,
            .next_sync_committee = undefined,
            .previous_epoch_participation = undefined,
            .current_epoch_participation = undefined,
        },
    };

    const epoch = getPreviousEpoch(&state);
    try std.testing.expectEqual(0, epoch);
}

test "test compute_activation_exit_epoch" {
    preset.ActivePreset.set(preset.Presets.mainnet);
    defer preset.ActivePreset.reset();
    const epoch = computeActivationExitEpoch(0);
    try std.testing.expectEqual(1 + preset.ActivePreset.get().MAX_SEED_LOOKAHEAD, epoch);

    const epoch2 = computeActivationExitEpoch(1);
    try std.testing.expectEqual(2 + preset.ActivePreset.get().MAX_SEED_LOOKAHEAD, epoch2);

    const epoch3 = computeActivationExitEpoch(2);
    try std.testing.expectEqual(3 + preset.ActivePreset.get().MAX_SEED_LOOKAHEAD, epoch3);
}
