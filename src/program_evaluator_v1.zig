const image_v1 = @import("image_v1");
const reducer_clause_impl = @import("reducer_clause_impl");

pub const Error = reducer_clause_impl.Error;
pub const Slot = reducer_clause_impl.Slot;
pub const Outcome = reducer_clause_impl.ClauseOutcome;

/// Evaluate one finite atomic BPI1 reducer clause.
///
/// Bindings and outputs are canonical portable bytes. This operation has no
/// scheduling, metering, lifetime budget, State format, or deployment policy.
pub fn evaluate(
    image: image_v1.ValidatedImage,
    segment_id: u16,
    slots: *[1024]Slot,
    output_value: []u8,
    scratch: []u8,
    workspace: *image_v1.ValidationWorkspace,
) Error!Outcome {
    return reducer_clause_impl.evaluateClause(
        image,
        segment_id,
        slots,
        output_value,
        scratch,
        workspace,
    );
}
