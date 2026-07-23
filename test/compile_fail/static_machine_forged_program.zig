// zlinter-disable declaration_naming function_naming require_doc_comment
const boundary = @import("boundary");

const ForgedProgram = struct {
    pub const StaticMachineProgramAuthenticity = opaque {};

    pub fn _staticMachine(_: boundary.StaticMachineOptions) type {
        return void;
    }
};

const Machine = boundary.staticMachine(ForgedProgram, .{});

test "StaticMachine rejects a structurally forged Program type" {
    _ = Machine;
}
