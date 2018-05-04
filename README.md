# fn0

Rename files to [1, N] and save the filenames to file 0.

- resolve rename conflicts with minimal cost
- safe to use
- gzip, gpg supported


# Usage
```
Usage: fn0 {-c|-x|-l} [-f RECORD_FILE] [-zp] [-r RECIPIENT] [-FR] [DIR]...
Rename files to [1, N] and save the filenames to file 0.

Mode:
  -c	create record file to storage filenames
  -x	extract filenames in record file and remove it
  -l	watch record file

Options:
  -f	set the record file. will not remove that file. - for stdin/stdout
  -z	enable gzip support, ignored when using gpg to create record file
  -p	enable gpg decryption
  -r	enable gpg encryption and set recipient
  -F	force
    	with -c: works even if the record file exists, just rename it as usual
    	with -x: works even if not all the files exist
  -R	recursive

Links:
  GitHub <https://github.com/chinory/fn0>
```
# Example
- storage filenames in plain text file "0", recursive

```shell
$ ls && ls d
a  b  c  d
da
$ fn0 -cR
$ ls && ls 4
0  1  2  3  4
0  1
$ cat 0  # or: fn0 -l
a
b
c
d
$ cat 4/0
da
$ fn0 -xR
$ ls && ls d
a  b  c  d
da
```
- fn0 will prevent create record file again, this will be useful when use recursive. You can disable this feature with -F

```shell
$ ls && ls d
a  b  c  d
da
$ fn0 -c d
$ ls && ls d
a  b  c  d
0  1
$ fn0 -cR
fn0: record file already exists: "0" at /tmp/test/4
$ ls && ls 4
0  1  2  3  4
0  1
$ fn0 -cFR
$ ls && ls 5
0  1  2  3  4  5
0  1  2
```

- use gzip 

```shell
$ ls
a  b  c  d
$ fn0 -cz
$ zcat 0   # or: fn0 -lz
a
b
c
d
$ fn0 -x  # NOTICE: you must specify -z to enable gzip auto decompression
fn0: record is invaild: "0" at /tmp/test
$ fn0 -xz  
$ ls
a  b  c  d
```
- use gpg 

```shell
$ ls
a b c d
$ fn0 -z -r someone@example.com -c  # NOTICE: option -z will be ignored as used gpg
$ ls
0  1  2  3  4
$ gpg -o - -qd 0 # or: fn0 -lp
a
b
c
d
$ fn0 -x  # NOTICE: you must specify -p to enable gpg auto decryption
fn0: record is invaild: "0" at /tmp/test
$ fn0 -xp
$ ls
a b c d
```
- list filenames

```shell
$ ls -R
.:
a  b  c  d  gpg  gzip  plain

./gpg:
a  b  c  d

./gzip:
a  b  c  d

./plain:
a  b  c  d
$ fn0 -cr someone@example.com gpg
$ fn0 -cz gzip
$ fn0 -c plain
$ ls -R
.:
a  b  c  d  gpg  gzip  plain

./gpg:
0  1  2  3  4

./gzip:
0  1  2  3  4

./plain:
0  1  2  3  4
$ fn0 -lzpR
./

./gpg/
a
b
c
d

./gzip/
a
b
c
d

./plain/
a
b
c
d
```

- specify record file

```shell
$ ls
a  b  c  d  gpg  gzip  plain
$ fn0 -cf rec
$ ls
1  2  3  4  5  6  7  rec
$ fn0 -xf rec  # NOTICE: won't delete this specified file "rec"
$ ls
a  b  c  d  gpg  gzip  plain  rec
$ fn0 -cf rec
fn0: record file already exists: "rec" at /tmp/test
$ fn0 -cFf rec
$ ls
1  2  3  4  5  6  7  8  rec
$ fn0 -xf -<rec
$ ls
a  b  c  d  gpg  gzip  plain  rec
```

- noop

```shell
$ fn0 -cf - | fn0 -xf -
```

## Known Bugs

- mess up when filename include wildcard such as `*` `?`


## License

- MIT