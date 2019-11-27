frr-fuzz
========

Patches, utilities, scripts and corpuses for fuzzing Free Range Routing.

Currently patched daemons:

- bgpd
- pimd

How to Fuzz
-----------
1. Clone this repository and my patched copy of FRR:

   ```
   git clone git@github.com:qlyoung/frr-fuzz.git
   git submodule update --init --recursive
   ```

2. Install FRR build dependencies for your platform

3. Install `afl` and `tmux`:

   ```
   apt install afl afl-clang tmux
   ```

4. Use the provided `install-frr.sh` to build and install FRR with AFL
   instrumentation, stack hardening and ASAN (yes, you should fuzz with ASAN):

   ```
   sudo ./install-frr -boiaf
   ```

5. Optional: add any additional input samples to the appropriate directory
   under `samples`. E.g. a new BGP packet sample should be placed in
   `samples/bgpd`, a new PIM sample in `samples/pimd`, etc. If you're only
   interested in one kind of packet, move or remove the samples you aren't
   interested from the directory.

6. Fuzz:

   ```
   sudo ./fuzz.sh <daemon> <cores>
   ```

   E.g. to fuzz `bgpd` with 15 cores:

   ```
   sudo ./fuzz.sh bgpd 15
   ```

   Wait.


Be forewarned that each AFL instance will completely consume one core. It is
best to leave at least one core for the rest of the system.

For information on AFL and how to interpret its status diplays, see the AFL
documentation.

Protip: read `Tips` at the bottom of this file.


How to Collect Results
----------------------

When AFL has found a crash, you'll want to get the crashing inputs. To do this
conveniently:

```
./collect-results <daemon>
```

Results will be placed in `out/<daemon>/results` and archived in
`./results.zip`.


How to Minimize Results
------------------------
When a crash is found, AFL will typically find a number of similar inputs that
cause the same crash. This is especially true when using parallel mode. It is
useful to reduce these to as few files as possible.

To do this:

1. Drop into a root shell
2. Set the environment variable `ASAN_OPTIONS` to `disable_leaks=0`
3. Run the following:

   ```
   cd out/<daemon>
   mkdir results-minimized
   afl-cmin -m none -i results -o results-minimized -- /usr/lib/frr/<daemon>
   ```


How to Debug Results
--------------------

* If you compiled with ASAN, ensure a working `llvm_symbolizer` is in your `PATH`.

* If you don't want to use ASAN for tracebacks - e.g. you prefer Valgrind, or
  want to debug with `gdb`, perform a clean compile of FRR:

  ```
  sudo git -C frr clean -fdx
  sudo ./install-frr.sh -boi
  ```

Then run the program with the crashing input:

```
/usr/lib/frr/<daemon> < <result>
```

If you compiled without ASAN and it doesn't crash, run it through Valgrind.
Lots of the memory bugs that cause crashes under ASAN do not crash without it,
but Valgrind can see them. If it's still not crashing, make sure you're on the
same source revision as the one `afl-fuzz` was using when it found the crash.


Tips
----
* It's best to let AFL reach at least 2 million execs before pulling the plug.
  Bugs have been found in `bgpd` at 30 million execs, around 8 hours of runtime
  on a 15 core machine. That's 5 days of melty CPU time.

* To stop fuzzing, use `tmux kill-session`. Results will be saved.

* `fuzz.sh` must be run as `root` because it uses cgroups to allow safely
  running AFL with no process memory limit, which is needed when using ASAN.

* The launcher script disables AFL's built-in CPU binding heuristics in favor
  of manually assigning cores, starting at 0. Make sure cores O to N, where N
  is the core count you gave `fuzz.sh`, are free.

* Protocol packets of high complexity, along with highly branched code paths,
  take much more time to test. You can help AFL discover new paths
  significantly faster, and with much higher probability, by providing highly
  complex sample inputs. For example, BGP fuzzing is significantly accelerated
  by providing an UPDATE packet stuffed with as many NLRIs and attributes as
  possible, rather than a minimal one.

* Network simulation tools such as mininet are very useful for gathering
  packets to use as input samples. All the current samples were collected this
  way.

* When adding new samples, if the input includes an IP header and the protocol
  checks source or destination IP, make sure you edit the input to use the ones
  expected by the daemon's fuzzing patch. You can do this with a hex editor.
  AFL will still permute these but it will quickly learn to leave them alone in
  order to get deeper into the program. Providing samples with incorrect IP
  headers means AFL has to stumble across the correct ones itself, which takes
  indeterminate time.

* Similarly, disabling checksums and tweaking enabled options in the fuzzing
  patches to various daemons could increase coverage if you feel you're not
  getting as far as you should be, although these should already be mostly
  disabled. When disabling checksums, don't disable the actual computation of
  the checksum - just make the validity check always pass.

* For performance reasons, AFL uses a deferred forkserver to test the target,
  meaning the binary is loaded once, interrupted roughly at `main()`, and then
  forked to make a new target process to fuzz. Consequently, it is possible to
  build, uninstall and reinstall FRR without interrupting or invalidating the
  current fuzzing process. However, it's still a bad idea due to performance
  concerns, memory concerns, the potential to touch files that might influence
  the fuzzed processes, etc. If possible, it's best to copy your results to
  another machine and work with them there.
