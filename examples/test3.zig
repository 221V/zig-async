
// workers with channels example

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
      std.time.sleep(std.time.ns_per_ms * 10); // 10 ms
    }
    
    var seed: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    //const rand_delay = randomInteger(&rand, 1, 5);
    const rand_delay = randomInteger(&rand, 10, 20);
    std.time.sleep(rand_delay * std.time.ns_per_s);
  }
}

pub fn main() !void{
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  defer _ = gpa.deinit();
  const allocator = gpa.allocator();
  
  // channels refs array - input per worker + output
  var input_channels: [WORKER_COUNT]*Channel(u32) = undefined;
  const output_channel: *Channel(u32) = try Channel(u32).init(allocator);
  
  // input channels init
  for(&input_channels) |*ch|{
    ch.* = try Channel(u32).init(allocator);
  }
  
  // channels deinit
  defer{
    for(input_channels) |ch|{ ch.deinit(); }
    output_channel.*.deinit();
  }
  
  // run workers, but every channel already is a thread
  for(0 .. WORKER_COUNT) |i|{
    _ = try Task(worker).launch(allocator, .{ input_channels[i], output_channel }); // run worker
    input_channels[i].push( @as(u32, @intCast(i + 1) ) ) catch unreachable; // tasks to worker
  }
  
  // collect results (must be inputs.len count)
  var received: usize = 0;
  while(received < WORKER_COUNT){
    if( output_channel.*.pop() ) |result|{
      print("Receive {d}\n", .{result});
      received += 1;
    }else{
      std.time.sleep(std.time.ns_per_ms * 5);
    }
  }
  
  //std.time.sleep(std.time.ns_per_s * 30); // 30 sec
  
  // stop - sentinel for workers
  for(&input_channels) |*ch|{
    ch.*.push(0) catch unreachable;
  }
  
  print("All done.\n", .{});
}


// this code creates 11 threads (tasks are executed in parallel)

// zig build-exe ./src/test3.zig -O ReleaseFast -femit-bin=test3
// ./test3
//Receive 1
//Receive 64
//Receive 27
//Receive 8
//Receive 125
//Receive 216
//Receive 343
//Receive 512
//Receive 729
//Receive 1000
//All done.

