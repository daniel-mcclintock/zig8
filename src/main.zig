const std = @import("std");
const log = std.log.info;
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
const OpCodeError = error{NotImplemented};

const V0 = 0;
const V1 = 1;
const V2 = 2;
const V3 = 3;
const V4 = 4;
const V5 = 5;
const V6 = 6;
const V7 = 7;
const V8 = 8;
const V9 = 9;
const VA = 10;
const VB = 11;
const VC = 12;
const VD = 13;
const VE = 14;
const VF = 15;
const PIXEL_ON = "\x1b[41m";
const PIXEL_OFF = "\x1b[0m";

const fontset: [80]u8 = .{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

const Chip8 = struct {
    //
    pc: u16 = 0x200,
    i: u16 = 0,
    registers: [16]u8 = .{0} ** 16,
    sp: u16 = 0,
    stack: [16]u16 = .{0} ** 16,
    delay_timer: u8 = 60,
    sound_timer: u8 = 60,
    rand: std.rand.Xoshiro256 = std.rand.DefaultPrng.init(0),
    memory: [4096]u8 = .{0} ** 4096,
    keys: [16]u8 = .{0} ** 16,
    gpu: GPU = GPU{},
};
const GPU = struct {
    memory: [64 * 32]u8 = .{0} ** (64 * 32),
    fn clear_display(self: *GPU) void {
        self.memory = .{0} ** (64 * 32);
    }
    fn render(self: *GPU) void {
        var i: u16 = 0;
        while (i < 64 * 32) : (i += 1) {
            if (i < self.memory.len and self.memory[i] == 255) {
                stdout.print("{s}  {s}", .{ PIXEL_ON, PIXEL_OFF }) catch {};
            } else {
                stdout.print("  ", .{}) catch {};
            }
            if (i % 64 == 0) {
                stdout.print("\n", .{}) catch {};
            }
        }
        stdout.print("\n", .{}) catch {};
    }
    fn draw_sprite(self: *GPU, chip8: *Chip8, x: u8, y: u8, h: u8) void {
        chip8.registers[VF] = 0;

        var col: u16 = 0;
        var row: u16 = 0;
        while (row < h) : (row += 1) {
            col = 0;
            var pixel = chip8.memory[chip8.i + row];

            while (col < 8) : (col += 1) {
                if (pixel & 0x80 == 0x80) {
                    // pixel is on
                    if (x + col >= 0 and y + row >= 0 and x + col < 64 and y + row < 32) {
                        if (self.memory[x + col + (@as(u16, y + row) * 64)] == 255) {
                            // screen pixel is on
                            self.memory[x + col + (@as(u16, y + row) * 64)] = 0;
                            chip8.registers[VF] = 1;
                        } else {
                            self.memory[x + col + (@as(u16, y + row) * 64)] = 255;
                        }
                    }
                }

                pixel <<= 1;
            }
        }
    }
    fn terminalSetup(termios: *std.os.linux.termios) void {
        // Disable echo, non-blocking reads
        termios.lflag &= ~std.os.linux.ECHO;
        termios.lflag &= ~std.os.linux.ICANON;

        _ = std.os.linux.tcsetattr(0, std.os.linux.TCSA.NOW, termios);
    }

    fn terminalReset(termios: *std.os.linux.termios) void {
        _ = std.os.linux.tcsetattr(0, std.os.linux.TCSA.NOW, termios);
    }
};

fn fetch(memory: *[4096]u8, pc: u16) u16 {
    return @as(u16, memory[pc]) << 8 | memory[pc + 1];
}

fn do(opcode: u16, chip8: *Chip8) !u8 {
    // NNN: address
    // NN: 8-bit constant
    // N: 4-bit constant
    // X and Y: 4-bit register identifier
    // PC : Program Counter
    // I : 16bit register (For memory address) (Similar to void pointer);
    // VN: One of the 16 available variables. N may be 0 to F (hexadecimal);
    switch (opcode & 0xF000) {
        0x0000 => {
            switch (opcode & 0x00FF) {
                0x00E0 => {
                    //00E0 - clear screen
                    chip8.gpu.clear_display();
                    return 1;
                },
                0x00EE => {
                    //00EE - return
                    chip8.sp -= 1;
                    chip8.pc = chip8.stack[chip8.sp];
                    return 1;
                },
                else => {
                    //0NNN - call
                    chip8.stack[chip8.sp] = chip8.pc;
                    chip8.sp += 1;
                    chip8.pc = opcode & 0x0FFF;
                    return 1;
                },
            }
            return OpCodeError.NotImplemented;
        },
        0x1000 => {
            //1NNN - goto NNN
            chip8.pc = (opcode & 0x0FFF);
            return 1;
        },
        0x2000 => {
            //2NNN - call subroutine
            chip8.stack[chip8.sp] = chip8.pc;
            chip8.sp += 1;
            chip8.pc = opcode & 0x0FFF;
            return 1;
        },
        0x3000 => {
            //3XNN - skip next instruction if VX does not equal NN
            if (chip8.registers[(opcode & 0x0F00) >> 8] != (opcode & 0x00FF) >> 8) {
                chip8.pc += 2;
            }
            return 1;
        },
        0x4000 => {
            //4XNN - skip next op if VX == NN
            if (chip8.registers[(opcode & 0x0F00) >> 8] != opcode & 0x00FF) {
                chip8.pc += 2;
            }
            return 1;
        },
        0x5000 => {
            //5XY0 - skip next op if VX == VY
            if (chip8.registers[(opcode & 0x0F00) >> 8] == opcode & 0x00FF) {
                chip8.pc += 2;
            }
            return 1;
        },
        0x6000 => {
            //6XNN
            chip8.registers[(opcode & 0x0F00) >> 8] = @intCast(u8, opcode & 0x00FF);
            return 1;
        },
        0x7000 => {
            //7XNN
            // add NN to VX
            var vx: u8 = undefined;
            _ = @addWithOverflow(u8, chip8.registers[(opcode & 0x0F00) >> 8], @intCast(u8, opcode & 0x00FF), &vx);
            chip8.registers[(opcode & 0x0F00) >> 8] = vx;
            return 1;
        },
        0x8000 => {
            //8XY0-8XY7-8XYE - arithmetic
            switch (opcode & 0x000F) {
                0x0000 => {
                    //8XY0 - VX = VY
                    chip8.registers[(opcode & 0x0F00) >> 8] = chip8.registers[(opcode & 0x00F0) >> 4];
                    return 1;
                },
                0x0001 => {
                    //8XY1 - VX |= VY
                    chip8.registers[(opcode & 0x0F00) >> 8] |= chip8.registers[(opcode & 0x00F0) >> 4];
                    return 1;
                },
                0x0002 => {
                    //8XY2 - VX &= VY
                    chip8.registers[(opcode & 0x0F00) >> 8] &= chip8.registers[(opcode & 0x00F0) >> 4];
                    return 1;
                },
                0x0003 => {
                    //8XY3 - VX ^= VY
                    chip8.registers[(opcode & 0x0F00) >> 8] ^= chip8.registers[(opcode & 0x00F0) >> 4];
                    return 1;
                },
                0x0004 => {
                    //8XY4 - VX += VY
                    if (@addWithOverflow(u8, chip8.registers[(opcode & 0x0F00) >> 8], chip8.registers[(opcode & 0x00F0) >> 4], &chip8.registers[(opcode & 0x0F00) >> 8])) {
                        chip8.registers[VF] = 1;
                    } else {
                        chip8.registers[VF] = 0;
                    }
                    return 1;
                },
                0x0005 => {
                    //8XY5 - VX -= VY
                    if (@subWithOverflow(u8, chip8.registers[(opcode & 0x0F00) >> 8], chip8.registers[(opcode & 0x00F0) >> 4], &chip8.registers[(opcode & 0x0F00) >> 8])) {
                        chip8.registers[VF] = 0;
                    } else {
                        chip8.registers[VF] = 1;
                    }
                    return 1;
                },
                0x0006 => {
                    //8XY6 - store least significant bit of VX in VF then VX >>= 1
                    if (chip8.registers[(opcode & 0x0F00) >> 8] & 0x1 == 0x1) {
                        chip8.registers[VF] = 1;
                    } else {
                        chip8.registers[VF] = 0;
                    }

                    chip8.registers[(opcode & 0x0F00) >> 8] >>= 1;
                    return 1;
                },
                0x0007 => {
                    //8XY7 - VX = VY - VX
                    if (@subWithOverflow(u8, chip8.registers[(opcode & 0x00F0) >> 4], chip8.registers[(opcode & 0x0F00) >> 8], &chip8.registers[(opcode & 0x0F00) >> 8])) {
                        chip8.registers[VF] = 0;
                    } else {
                        chip8.registers[VF] = 1;
                    }
                    return 1;
                },
                0x000E => {
                    //8XYE - store most significant bit of VX in VF then VX <<=1
                    if (chip8.registers[(opcode & 0x0F00) >> 8] & 0x80 == 0x80) {
                        chip8.registers[VF] = 1;
                    } else {
                        chip8.registers[VF] = 0;
                    }

                    chip8.registers[(opcode & 0x0F00) >> 8] <<= 1;
                    return 1;
                },
                else => {},
            }
        },
        0x9000 => {
            //9XY0 - skips the next op if VX != VY
            if (chip8.registers[(opcode & 0x0F00) >> 8] != chip8.registers[(opcode & 0x00F0) >> 8]) {
                chip8.pc += 2;
            }
            return 1;
        },
        0xA000 => {
            //ANNN
            chip8.i = opcode & 0x0FFF;
            return 1;
        },
        0xB000 => {
            //BNNN - jump to V0 + NNN
            chip8.pc = chip8.registers[V0] + (opcode & 0x0FFF);
            return 1;
        },
        0xC000 => {
            //CXNN - rand, VX = rand() & NN
            chip8.registers[(opcode & 0x0F00) >> 8] = @intCast(u8, opcode & 0x00FF) & chip8.rand.random().int(u8);
            return 1;
        },
        0xD000 => {
            //DXYN - draw sprite
            var x = chip8.registers[(opcode & 0x0F00) >> 8];
            var y = chip8.registers[(opcode & 0x00F0) >> 4];
            var n = @intCast(u8, opcode & 0x000F);
            chip8.gpu.draw_sprite(chip8, x, y, n);
            return 1;
        },
        0xE000 => {
            switch (opcode & 0x00FF) {
                0x009E => {
                    //EX9E - skips the next op if the key referenced by VX is pressed
                    if (chip8.keys[chip8.registers[(opcode & 0x0F00) >> 8]] == 0) {
                        chip8.pc += 2;
                    }
                    return 1;
                },
                0x00A1 => {
                    //EXA1 - skips the next op if the key referenced by VX is not pressed
                    if (chip8.keys[chip8.registers[(opcode & 0x0F00) >> 8]] != 0) {
                        chip8.pc += 2;
                    }
                    return 1;
                },
                else => {},
            }
        },
        0xF000 => {
            switch (opcode & 0x00FF) {
                0x0007 => {
                    //FX07 - set VX to delay_timer value
                    chip8.registers[(opcode & 0x0F00) >> 8] = chip8.delay_timer;
                    return 1;
                },
                0x000A => {
                    //FX0A - set wait, halt until key pressed
                    //TODO: hack. just pass
                    return 1;
                },
                0x0015 => {
                    //FX15 - set delay timer to VX
                    chip8.delay_timer = chip8.registers[(opcode & 0x0F00) >> 8];
                    return 1;
                },
                0x0018 => {
                    //FX18 - set sound timer to VX
                    chip8.sound_timer = chip8.registers[(opcode & 0x0F00) >> 8];
                    return 1;
                },
                0x001E => {
                    //FX1E - adds VX to I, VF is not affected
                    _ = @addWithOverflow(u16, chip8.i, @as(u16, chip8.registers[(opcode & 0x0F00) >> 8]), &chip8.i);
                    return 1;
                },
                0x0029 => {
                    //FX29 - set i to the addr of the fontchar for the char vx
                    // the fontset storage starts at 0x50, fonts are 4*5
                    // 0 = 0x50 = 0x50 + 0*5
                    // 1 = 0xA0 = 0x50 + 1*5
                    // 2 = 0xF0 = 0x50 + 2*5
                    // etc
                    chip8.i = 0x50 + (chip8.registers[(opcode & 0x0F00) >> 8] * 5);
                    return 1;
                },
                0x0033 => {
                    //FX33 - store the 3 most significant digits of the
                    //binary coded decimal rep of vx at the address in I.
                    var vx = chip8.registers[(opcode & 0x0F00) >> 8];
                    chip8.memory[chip8.i] = vx / 100;
                    vx %= 100;
                    chip8.memory[chip8.i + 1] = vx / 10;
                    chip8.memory[chip8.i + 2] = vx % 10;
                    return 1;
                },
                0x0055 => {
                    //FX55 - stores V0 to VX in memory starting at address I
                    for (chip8.registers[V0 .. (opcode & 0x0F00) >> 8]) |value, register| {
                        chip8.memory[chip8.i + register] = value;
                    }
                    return 1;
                },
                0x0065 => {
                    //FX65 - fill registers v0 to vx with offset values from
                    //memory at the address i+n
                    for (chip8.registers[V0 .. (opcode & 0x0F00) >> 8]) |_, register| {
                        chip8.registers[register] = chip8.memory[chip8.i + register];
                    }
                    return 1;
                },
                else => {},
            }
            return OpCodeError.NotImplemented;
        },
        else => {},
    }
    return OpCodeError.NotImplemented;
}

fn dump(chip8: *Chip8, opcode: u16) !void {
    stdout.print("pc: {d} | op: 0x{x} | i: {x}\nregisters -> ", .{ chip8.pc, opcode, chip8.i }) catch {};
    stdout.print("V0: 0x{x}, V1: 0x{x}, V2: 0x{x}, V3: 0x{x}, V4: 0x{x}, V5: 0x{x}, V6: 0x{x}, V7: 0x{x}\n", .{ chip8.registers[V0], chip8.registers[V1], chip8.registers[V2], chip8.registers[V3], chip8.registers[V4], chip8.registers[V5], chip8.registers[V6], chip8.registers[V7] }) catch {};
    stdout.print("registers -> V8: 0x{x}, V9: 0x{x}, VA: 0x{x}, VB: 0x{x}, VC: 0x{x}, VD: 0x{x}, VE: 0x{x}, VF: 0x{x}", .{ chip8.registers[V8], chip8.registers[V9], chip8.registers[VA], chip8.registers[VB], chip8.registers[VC], chip8.registers[VD], chip8.registers[VE], chip8.registers[VF] }) catch {};
    stdout.print("\n", .{}) catch {};
}

fn use(rom: []const u8, step: bool, render: bool) !void {
    var opcode: u16 = 0;
    var chip8 = Chip8{};

    var f: std.fs.File = try std.fs.cwd().openFile(rom, .{});
    _ = try f.read(chip8.memory[512..4096]);

    for (fontset) |char, index| {
        chip8.memory[0x50 + index] = char;
    }

    while (chip8.pc < chip8.memory.len) {
        if (render) {
            stdout.print("\x1b[2J", .{}) catch {};
            chip8.gpu.render();
        }
        opcode = fetch(&chip8.memory, chip8.pc);
        try dump(&chip8, opcode);
        chip8.pc += 2;
        var time = do(opcode, &chip8) catch {
            stdout.print(" -> NotImplemented\n", .{}) catch {};
            break;
        };

        if (step) {
            _ = stdin.readByte() catch {};
        } else {
            std.time.sleep(@as(u32, time) * 7500000);
        }

        if (chip8.delay_timer > 1) {
            chip8.delay_timer -= 1;
        }
        if (chip8.sound_timer > 1) {
            chip8.sound_timer -= 1;
        }

        // keys
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var render = true;
    var step_through = false;

    var termios: std.os.linux.termios = undefined;
    _ = std.os.linux.tcgetattr(0, &termios);
    var old_termios = termios;

    GPU.terminalSetup(&termios);
    defer GPU.terminalReset(&old_termios);

    try use(args[1], step_through, render);
}
