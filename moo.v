import io
import net
import os
import os.cmdline
import crypto.rand
import sokol.sapp
import math
import gg
import gx
import strconv

type FN = fn (mut TOOB, ...string) ?f64
type ESC = map[string]FN

fn mkesc() ESC {
	return map[string]FN{}
}

@[heap]
struct TOOB {
pub  mut:
	ops ESC
	a f64
	b f64
	code_roll u32
	ev_wok string
	wok string
	str []string
	working f64
	working_bool bool
	stack [][]u8
	code []string
	strings map[string]string
	bytes map[string][]u8
	numbers map[string]f64
	unsigned_numbers map[string]f64
	state map[string]int
	events map[string][]fn(ev &gg.Event)
	dropped_file_list []string
	draw_calls map[int]fn (mut TOOB)
	gg &gg.Context = unsafe { nil }
}

fn (mut tb TOOB) store_bytes(moniker string, value []u8) {
	tb.bytes[moniker] = value
}

fn (mut tb TOOB) store_string(moniker string, value string) {
	tb.strings[moniker] = value
}

fn (mut tb TOOB) store_f64(moniker string, value f64) {
	tb.numbers[moniker] = value
}

fn (mut tb TOOB) read_str(moniker string) ?string {
	return tb.strings[moniker]
}

fn (mut tb TOOB) read_f64(moniker string) ?f64 {
	if n := tb.numbers[moniker] {
		return n
	}
	return none
}

fn (mut tb TOOB) store_handle(label string, contents []string) ?f64 {
    mut subspace_stack := []string{} // Stack for nested subspaces (e.g., ["work", "sub"])
    mut i := 0

    for i < contents.len {
        item := contents[i]

        // Handle subspace delimiters
        if item == "," {
            if subspace_stack.len > 0 {
                subspace_stack.pop() // Close the most recent subspace
                // println("closed subspace: ${subspace_stack}")
            }
            i++
            continue
        }

        // Check if this is a subspace opener (ends with ":")
        if item.ends_with(":") {
            subspace_stack << item.trim_right(":")
            // println("opened subspace: ${subspace_stack}")
            i++
            continue
        }

        // Must have a value next
        if i + 1 >= contents.len {
			println("error in store_handle: missing value for prop '${item}' at index ${i}")
            return -1
        }
        val := contents[i + 1]

        // Build the full key with dot notation
        mut full_key := label
        for sub in subspace_stack {
            full_key += "." + sub
        }
        full_key += "." + item

        // Type inference and storage
        if val.contains(".") || (val.len > 0 && (val[0] == `-` || (val[0] >= `0` && val[0] <= `9`))) {
            if f := strconv.atof64(val) {
                tb.store_f64(full_key, f)
                // println("stored ${full_key}: ${f} (f64)")
            } else {
                tb.store_string(full_key, val)
                // println("stored ${full_key}: ${val} (string, failed f64 parse)")
            }
        } else {
            tb.store_string(full_key, val)
            // println("stored ${full_key}: ${val} (string)")
        }

        i += 2 // Move to next prop-value pair or comma
    }

	return none
}

fn (mut tb TOOB) interpret(source string) {
	mut mode := u8(0)
	mut sub_mode := u8(0)
	mut current_op := ""
	mut to_print := ""
    mut current_args := []string{cap: 32}
    mut working_buf := []u8{cap: 512}
	mut stored_label := ""
	mut conditional_skip := false
	mut i := -1
	for {
		if i > source.len { break } else { i++ }
		mut c := source[i] or { break }
		match mode {
			0 { // default
				match c {
					`:` {
						do_op: if current_op != "" && !conditional_skip {
							if sub_mode == 1 && stored_label != "" {
								//println("labelcatch: running current_op ${stored_label}: ${current_op} with ${current_args}")
								if stored_label == "2" {
									mut args := []string{}
									mut args2 := []string{}
									mut twiddle := false
									for arg in current_args {
										if twiddle {
											args2 << arg
											twiddle = false
										} else {
											args << arg
											twiddle = true
										}
									}
									tb.run(current_op, ...args)
									tb.run(current_op, ...args2)
								} else {
									code := tb.run(current_op, ...current_args) 
									if code != none && stored_label != "" {
										tb.state[stored_label] = int(code)
									}
								}
							} else {
								//println("labelcatch: running ${current_op} with ${current_args}")
								tb.run(current_op, ...current_args)
							}
							current_op = ""
							stored_label = ""
							current_args.clear()
							sub_mode = 0
						}

						conditional_skip = false
						stored_label = working_buf.bytestr()
						working_buf.clear()
						//println("found label called ${stored_label}")

						mut rest := "" // print("\nat i ${i}")
						mut tmp := []string{}
						for {
							i += 1
							if i == source.len { break }
							c = source[i]
							if c != ` ` && c != `\t` && c != `\n` {
								if c == `;` {
									//println("caught struct mode: ${stored_label}: ${tmp};")
									tmp << rest
									rest = ""
									tb.store_handle(stored_label, tmp)
									stored_label = ""
									break
								}
								if c == `,` {
									if rest.len == 0 { continue }
									tmp << rest
									rest = ""
								}
								rest += c.ascii_str()
							} else {
								if rest in tb.ops || c == `\`` {
									current_op = rest
									current_args.clear()
									sub_mode = 1
									break
								} else {
									if rest.len == 0 { continue }
									if rest.starts_with('"') && rest.ends_with('"') {
										rest = rest.trim('"')
									}
									tmp << rest
									rest = ""
								}
							}
						} // print("...\t now at i ${i} of ${source.len} \n ")
					}
					`"` { mode = 1 } // quote
					`|` { mode = 2 } // comment
					`\`` { mode = 3 } // print
					`$` { mode = 4 } // struct
					`=` {
						mut rest := "" // print("\nat i ${i}")
						mut tmp := []string{}
						mut quoted := false
						for {
							i += 1
							if i == source.len { break }
							c = source[i]
							if (c == ` ` || c == `\n`) && tmp.len != 0 {
								if !quoted {
									tmp << rest.trim_space()
									rest = ""
									eq_check: if tmp.len == 2 {
										if tmp[0][0] == `~` {
											tmp[0] = tb.strings[tmp[0].trim_left("~")]
										}
										if tmp[1][0] == `~` {
											tmp[1] = tb.strings[tmp[1].trim_left("~")]
										}
										tb.working_bool = tmp[0] == tmp[1]
										break
									}
								} else {
									panic("syntax error: conditional quotes are uneven, put one in at the end ${i}")
								}
							} else if c == `"` {
								if quoted {
									quoted = false
									tmp << rest
									rest = ""
									unsafe { goto eq_check }
								} else {
									quoted = true
								}
							} else if c == `?` || c == `!` {
								if rest.len > 0 {
									tmp << rest.trim('"').trim_space()
								}
								conditional_skip = if c == `!` { tb.working_bool } else { !tb.working_bool }
								unsafe { goto eq_check }
							} else {
								if c == ` ` && !quoted && rest.len > 0 {
									tmp << rest.trim_left(" ")
									rest = ""
									unsafe { goto eq_check }
								}
								rest += c.ascii_str()
							}
						}
					}
					`?` {
						conditional_skip = !tb.working_bool
					}
					`!` {
						conditional_skip = tb.working_bool
					}
					`;` { stored_label = "" }
					else {
						if c == ` ` || c == `\n` {
							op_run:
							mut wok := working_buf.bytestr().trim_space()
							working_buf.clear()
							if wok.len == 0 { continue }
							if wok in tb.ops && !conditional_skip {
								if sub_mode == 1 && stored_label != "" {
									//println("labelcatch: running current_op ${stored_label}: ${current_op} with ${current_args}")
									if stored_label == "2" {
										mut args := []string{}
										mut args2 := []string{}
										mut twiddle := false
										for arg in current_args {
											if twiddle {
												args2 << arg
												twiddle = false
											} else {
												args << arg
												twiddle = true
											}
										}
										tb.run(current_op, ...args)
										tb.run(current_op, ...args2)
									} else {
										code := tb.run(current_op, ...current_args) 
										if code != none && stored_label != "" {
											tb.state[stored_label] = int(code)
										}
									}
								} else {
									//println("labelcatch: running ${current_op} with ${current_args}")
									tb.run(current_op, ...current_args)
								}
								current_op = ""
								stored_label = ""
								current_args.clear()
								sub_mode = 0
								current_op = wok
								sub_mode = 0
							} else {
								current_args << wok
								sub_mode = 1
								if i == source.len - 1 { // println("arg insert last for op: ${current_op} with ${current_args} and working_buf is still ${working_buf.bytestr()}")
									if current_op != "" { unsafe { goto do_op } }
								}
							}
						} else {
							working_buf << c
							if i == source.len - 1 { //println("goto: op_run and current_op is  ${current_op} ${current_args} and working_buf is still ${working_buf.bytestr()}")
								unsafe {  goto op_run }
							}
						}
					}
				}
			}
			1 { // quote
				if c == `"` {
					mode = 0
					current_args << working_buf.bytestr()
					working_buf.clear()
				} else { working_buf << c }
			}
			2 { if c == `|` { mode = 0 } } // comment
			3 { // printing
				match c {
					`\`` {
						if current_op != "" && !conditional_skip {
							if sub_mode == 1 && stored_label != "" {
							//println("labelcatch: running current_op ${stored_label}: ${current_op} with ${current_args}")
							if stored_label == "2" {
								mut args := []string{}
								mut args2 := []string{}
								mut twiddle := false
								for arg in current_args {
									if twiddle {
										args2 << arg
										twiddle = false
									} else {
										args << arg
										twiddle = true
									}
								}
								tb.run(current_op, ...args)
								tb.run(current_op, ...args2)
							} else {
								code := tb.run(current_op, ...current_args) 
								if code != none && stored_label != "" {
									tb.state[stored_label] = int(code)
								}
							}
						} else {
							//println("labelcatch: running ${current_op} with ${current_args}")
							tb.run(current_op, ...current_args)
						}
						conditional_skip = false
						current_op = ""
						stored_label = ""
						current_args.clear()
						sub_mode = 0
						}

						mut final_print := ""
						to_print = working_buf.bytestr() // Keep raw string with newlines
						working_buf.clear()
						lines := to_print.split("\n")
						for line in lines {
							mut line_print := ""
							// Split words but keep original spacing
							words := line.split(" ")
							for j, word in words {
								if word.starts_with("~") {
									key := word.trim_left("~")
									if replacement := tb.strings[key] {
										line_print += replacement
									} else if replacement := tb.numbers[key] {
										line_print += replacement.str()
									} else {
										line_print += "__did not find ${key}__"
									}
								} else {
									line_print += word
								}
								// Add space only if not the last word in the line
								if j < words.len - 1 {
									line_print += " "
								}
							}
							final_print += line_print + "\n"
						}
						print(final_print) // Print with newlines preserved
						mode = 0
						sub_mode = 0
					}
					else {
						working_buf << c
					}
				}
			}
			4 { // struct"ured addressing"
			}
			else {
				print("whut? mode mood.. unknown")
			}
		}
	}
	if current_op != "" && !conditional_skip { 
		if sub_mode == 1 && stored_label != "" {
			//println("labelcatch: running current_op ${stored_label}: ${current_op} with ${current_args}")
			if stored_label == "2" {
				mut args := []string{}
				mut args2 := []string{}
				mut twiddle := false
				for arg in current_args {
					if twiddle {
						args2 << arg
						twiddle = false
					} else {
						args << arg
						twiddle = true
					}
				}
				tb.run(current_op, ...args)
				tb.run(current_op, ...args2)
			} else {
				code := tb.run(current_op, ...current_args) 
				if code != none && stored_label != "" {
					tb.state[stored_label] = int(code)
				}
			}
		} else {
			//println("labelcatch: running ${current_op} with ${current_args}")
			tb.run(current_op, ...current_args)
		}
		conditional_skip = false
		current_op = ""
		stored_label = ""
		current_args.clear()
		sub_mode = 0
	}
	println("finish'd")
}

fn toob() TOOB {
	return TOOB{
		ops: mkesc(),
		a: 0,
		b: 0,
		code_roll: 0,
		working: 0,
		wok: "",
		ev_wok: "",
		working_bool: false,
		draw_calls: map[int] fn (mut TOOB) {},
		state: map[string]int{},
		events: map[string][]fn(ev &gg.Event)
	}
}

fn (mut tb TOOB) intervene(action fn (mut TOOB)) TOOB {	
	action(mut tb)
	return tb
}

fn (mut tb TOOB) run(op string, args ...string) ?f64 {
	if op in tb.ops {
		tb.code << op
		return tb.ops[op](mut tb, ...args)
	}
	return none
}

fn (mut tb TOOB) draw_call(call fn (mut TOOB)) int {
	if i := rand.int_u64(100000) {
		n := int(i)
		tb.draw_calls[n] = call
		return n
	}
	return -1
}

fn (mut tb TOOB) draw_uncall(i int) {
	tb.draw_calls.delete(i)
}

fn frame(mut tb TOOB) {
	tb.gg.begin()
	for _, call in tb.draw_calls { call(mut tb) }
	tb.gg.end()
}

fn evloop(mut ev gg.Event, mut tb TOOB) {
	// drag&drop event
	if ev.typ == .files_dropped {
		num_dropped := sapp.get_num_dropped_files()
		tb.dropped_file_list.clear()
		for i in 0 .. num_dropped {
			tb.dropped_file_list << sapp.get_dropped_file_path(i)
		}
	} else {
		for ln in tb.events[ev.typ.str()] {
			go ln(&ev)
		}
		if tb.ev_wok != ev.typ.str() {
			tb.ev_wok = ev.typ.str()
		}
	}
}

fn main() {
	mut tb := toob()
	tb.gg = gg.new_context(
		user_data: &tb,
		bg_color:     gx.rgb(232, 216, 199)
		width:        800
		height:       600
		window_title: 'moo moo'
		frame_fn:     frame,
		event_fn: evloop
	)
	tb.ops["box"] = fn (mut tb TOOB, args ...string) ?int {
		x := f32(strconv.atof64(args[0]) or { 0 })
		y := f32(strconv.atof64(args[1]) or { 0 })
		w := f32(strconv.atof64(args[2]) or { 0 })
		h := f32(strconv.atof64(args[3]) or { 0 })
		color := gx.color_from_string(args[4])
		// x u16, y u16, w u16, h u16
		return tb.draw_call(fn [x,y,w,h,color](mut tb TOOB) {
			tb.gg.draw_rect(gg.DrawRectParams{
				x: x,
				y: y,
				w: w,
				h: h,
				color: color,
			})
		})
	}

	tb.ops["unrendr"] = fn (mut tb TOOB, args ...string) ?f64 {
		for arg in args {			
			if arg in tb.state {
				println("unrendring ${arg} as tb.draw_uncall(${tb.state[arg]}) from ${tb.state}")
				tb.draw_uncall(tb.state[arg])
				tb.state.delete(arg)
				println("unrendring left these ${tb.state}")
			}
		}
		return none
	}

	tb.ops["txt"] = fn (mut tb TOOB, args ...string) ?f64 {
		txt := args[0]
		x := strconv.atoi(args[1]) or { 0 }
		y := strconv.atoi(args[2]) or { 0 }
		s := strconv.atoi(args[3]) or { 0 }
		mw := strconv.atoi(args[4]) or { 0 }
		color := gx.color_from_string(args[5])
		// x u16, y u16, w u16, h u16
		return tb.draw_call(fn [txt,x,y,s,mw,color](mut tb TOOB) {
			tb.gg.draw_text2(gg.DrawTextParams{
				text: txt,
				x: x,
				y: y,
				size: s,
				max_width: mw,
				color: color,
			})
		})
	}

	tb.ops["@"] = fn (mut tb TOOB, args ...string) ?f64 {
		if script := tb.strings[args[0]] {
			tb.interpret(script)
			return 1
		} else {
			script := os.read_file("./" + args[0] + ".moo") or { panic(err) }
			tb.interpret(script)
			return 1
		}
		return none
	}

	tb.ops["write"] = fn (mut tb TOOB, args ...string) ?f64 {
		if args[1][0] == `~` {
			os.write_file(args[0], tb.strings[args[1].trim_left("~")]) or { panic(err) }
		} else {
			os.write_file(args[0], args[1]) or { panic(err) }
		}
		return none
	}

	tb.ops["read"] = fn (mut tb TOOB, args ...string) ?f64 {
		contents := os.read_file(args[0]) or { panic(err) }
		tb.strings[args[1]] = contents
		return none
	}

	tb.ops["*f64"] = fn (mut tb TOOB, args ...string) ?f64 {
		if prop := tb.read_f64(args[0]) {
			tb.working = prop
			return tb.working
		}
		return none
	}

	tb.ops["*str"] = fn (mut tb TOOB, args ...string) ?f64 {
		if prop := tb.read_str(args[0]) {
			tb.wok = prop
			return 1
		}
		return none
	}

	tb.ops["f64"] = fn (mut tb TOOB, args ...string) ?f64 {
		tb.numbers[args[0]] = strconv.atof64(args[1]) or { return 0 }
		return 1
	}

	tb.ops["str"] = fn (mut tb TOOB, args ...string) ?f64 {
		if args.len != 0 {
			tb.strings[args[0]] = args[1]
		} 
		return 1
	}

	tb.ops["+"] = fn (mut tb TOOB, args ...string) ?f64 {
		tb.working = tb.a + tb.b
		return tb.working
	}
	tb.ops["-"] = fn (mut tb TOOB, args ...string) ?f64 {
		tb.working = tb.a - tb.b
		return tb.working
	}
	tb.ops["*"] = fn (mut tb TOOB, args ...string) ?f64 {
		tb.working = tb.a * tb.b
		return tb.working
	}
	tb.ops["/"] = fn (mut tb TOOB, args ...string) ?f64 {
		tb.working = tb.a / tb.b
		return tb.working
	}
	tb.ops["**"] = fn (mut tb TOOB, args ...string) ?f64 {
		tb.working = math.pow(tb.a, tb.b)
		return tb.working
	}
	tb.ops["a"] = fn (mut tb TOOB, args ...string) ?f64 {
		return tb.a
	}
	tb.ops["b"] = fn (mut tb TOOB, args ...string) ?f64 {
		return tb.b
	}
	tb.ops["pop_str"] = fn (mut tb TOOB, args ...string) ?f64 {
		tb.wok = tb.str.pop()
		return none
	}

	spawn tb.gg.run()
	mut server := net.listen_tcp(.ip6, ':16842') or { panic(err) }
	laddr := server.addr() or { panic(err) }
	eprintln('moo.v runing on ${laddr} ...')
	mut sockets := chan &net.TcpConn{}
	spawn fn [mut sockets, mut tb]() {
		for {
			if mut socket := <- sockets {
				go handle_client(mut socket, tb.abp)
			}
		}
	}()

	// tb.interpret() run_script
	mut src := cmdline.option(os.args, 'src', "./main.moo").str()
	tb.interpret(os.read_file(src) or { panic(err) })

	for {
		mut socket := server.accept() or { panic(err) }
		sockets <- socket
	}
}

fn (mut tb TOOB) abp(b bool, i u8, mut working map[u8][]u8) bool { // flag byte initial spit balling
	mut o := false
	if b {
		match i {
			0 {
				
			}
			1 { // txt / bin

			}
			2 {} // if text, 
			3 {}
			4 {}
			5 {}
			6 {}
			7 {}
			8 {}
			else {}
		}
	} else { // output
		match i {
			0 { 
				
			}
			1 {

			}
			2 {} // if text, 
			3 {}
			4 {}
			5 {}
			6 {}
			7 {}
			8 {}
			else {}
		}
	}
	return o
}

fn treat_4_2bits(b u8, bit_callback fn (bool, u8, mut map[u8][]u8) bool) u8 {
	mut acc := []bool{cap:8}
	mut working := map[u8][]u8{}
	if b == 255 { // flush means we do 2 bit protocol instead of 4 bit 5 bit based flip flop
		working[255][255] = 1
		return b
	}
	for i := 0; i < 8; i++ { acc << bit_callback((b >> i) & 1 == 1, u8(i), mut working) }
	mut res := u8(0)
    for i, bit in acc { if bit { res |= (1 << i) } }
    return res
}

fn handle_client(mut socket net.TcpConn, bcb fn (bool, u8, mut map[u8][]u8) bool) {
	client_addr := socket.peer_addr() or { return }
	eprintln('> new client: ${client_addr}')
	mut reader := io.new_buffered_reader(reader: socket)
	mut bytes := []u8{cap: 4096 * 16}
	mut out := []u8{cap: 4096 * 4}
	for {
		/*n := */reader.read(mut bytes) or { break }
		for { 
			if bytes.len != 0 {
				out << treat_4_2bits(bytes.pop(), bcb)
			}
		}
	}
	unsafe {
		reader.free()
		free(bytes)
	}
	socket.write(out) or { print("couldn't echo back") }
	socket.close() or { print(err) }
}


/*
fn bool_pair(a bool, b bool) []bool {
	return [a, b]
}
fn toob_runnr(raw []u8) {
	// res |= (1 << i)
	for b in raw {
		b1p1 := (b >> 0) & 1 == 1
		b2p1 := (b >> 1) & 1 == 1
		b1p2 := (b >> 2) & 1 == 1
		b2p2 := (b >> 3) & 1 == 1
		b1p3 := (b >> 4) & 1 == 1
		b2p3 := (b >> 5) & 1 == 1
		b1p4 := (b >> 6) & 1 == 1
		b2p4 := (b >> 7) & 1 == 1

		/*
			00 = slotA memory [0, 1, 2, [3, 4, 5, [6, 7, 8, [...]]]]
			01 = slotB persistent memory [0, 1, 2, [3, 4, 5, [6, 7, 8, [...]]]]
			10 = operation cycler [store, load, [pop, is_eq, swap, [...]], [add, sub, mul, [div, exponentiate, root, [...]]]]
			11 = escape [str, [u8, u16, u32, [u64, f64, int, [...]]], [array, while_loop], [...]]
		*/

		mut cycler := -1
		mut slota := 0
		mut slotb := 0
		mut esc_lvl := 0

		if b1p1 {if b2p1 {
			slota += 1
		} else {
			slotb += 1
		}} else if b2p1 {
			cycler += 1
		} else {
			esc_lvl += 1
		}

		if b1p2 {if b2p2 {
			slota += 1
		} else {
			slotb += 1
		}} else if b2p2 {

		} else {

		}

		if b1p3 {if b2p3 {

		} else {

		}} else if b2p3 {

		} else {

		}

		if b1p4 {if b2p4 {

		} else {

		}} else if b2p4 {

		} else {

		}
	}
}*/
