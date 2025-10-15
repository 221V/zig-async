
// workers with channels per thread example

const std = @import("std");
const print = std.debug.print;

//const Future = @import("zig_async_jack_ji/task.zig").Future;
const Task = @import("zig_async_jack_ji/task.zig").Task;
const Channel = @import("zig_async_jack_ji/channel.zig").Channel;

const WORKER_COUNT: usize = 10;


fn randomInteger(rand: *const std.Random, min: u32, max: u32) u32{
  return rand.intRangeLessThan(u32, min, max + 1);
}


// worker that with own channels
fn worker(input_ch: *Channel(u32), output_ch: *Channel(u32)) void{
  while(true){
    const maybe_num = input_ch.pop();
    if(maybe_num) |num|{
      if(num == 0){ break; } // sentinel
      const cube = num * num * num;
      output_ch.push(cube) catch unreachable;
    }else{
      std.time.sleep(std.time.ns_per_ms * 10);
    }
    
    var seed: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const rand_delay = randomInteger(&rand, 1, 5);
    std.time.sleep(rand_delay * std.time.ns_per_s);
    
  }
}

pub fn main() !void{
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  defer _ = gpa.deinit();
  const allocator = gpa.allocator();
  
  // channels refs array - input + output per worker
  var input_channels: [WORKER_COUNT]*Channel(u32) = undefined;
  var output_channels: [WORKER_COUNT]*Channel(u32) = undefined;
  
  // channels init
  for(&input_channels) |*ch|{
    ch.* = try Channel(u32).init(allocator);
  }
  for(&output_channels) |*ch|{
    ch.* = try Channel(u32).init(allocator);
  }
  
  // channels deinit
  defer{
    for(input_channels) |ch|{ ch.deinit(); }
    for(output_channels) |ch|{ ch.deinit(); }
  }
  
  // run workers in threads
  var threads: [WORKER_COUNT]std.Thread = undefined;
  for(&threads, 0..) |*thread, i|{
    thread.* = try std.Thread.spawn(.{}, worker, .{ input_channels[i], output_channels[i] });
  }
  
  const inputs = [_]u32{ 2, 3, 4, 5, 6 };
  
  // tasks to workers
  var worker_index: usize = 0;
  for(inputs) |num|{
    input_channels[worker_index].push(num) catch unreachable;
    worker_index = (worker_index + 1) % WORKER_COUNT;
  }
  
  // stop - sentinel for workers
  for(&input_channels) |*ch|{
    ch.*.push(0) catch unreachable;
  }
  
  // collect results (must be inputs.len count)
  var received: usize = 0;
  while(received < inputs.len) : (received += 1){
    var found = false;
    while(!found){
      for(&output_channels) |*ch|{
        if( ch.*.pop() ) |result|{
          print("Receive {d}\n", .{result});
          found = true;
          break;
        }
      }
      if(!found){
        std.time.sleep(std.time.ns_per_ms * 5);
      }
    }
  }
  
  // waiting all threads ends
  for(&threads) |*thread|{
    thread.join();
  }
  
  print("All done.\n", .{});
}


// zig build-exe ./src/test3.zig -O ReleaseFast -femit-bin=test3
// ./test3
//Receive 27
//Receive 64
//Receive 216
//Receive 125
//Receive 8
//All done.

