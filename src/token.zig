// INFO: try to not forget to update info in help command when changing operations
pub const OpType = enum {
    add,
    sub,
    mul,
    div,
    mod,
    neg,
    abs,
    min,
    max,
    dup,
    swap,
    drop,
    over,
    rot,
    clear,
    print,
    peek,
    stack,
    quit,
    help,
};

pub const Token = union(enum) {
    int: i32,
    float: f64,
    bool: bool,
    op: OpType,
};
