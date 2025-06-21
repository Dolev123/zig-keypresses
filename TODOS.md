# TODOs:

All the staff that is still work in progress, but not code.  

## Translations

```sh
# run and check syscalls, and log output
sudo strace -e trace=ioctl,openat ./zig-out/bin/main -d /dev/input/event3 >/tmp/log
# look at output
watch tail -n40 /tmp/log
```

- [ ] Check for pressing/releasing <Shift> <CAPS> <ALT> <CTRL>, and save their state.
- [ ] Find relevant user's tty. `strace who`?
- [ ] Find currently used keyboard layout.
