# Testing auspex

Auspex is tested on its own fleet set from
[hoon-development](https://github.com/nisfeb/hoon-development), never on
`~ricsul-bilwyt`. A push to `master` is a release (docs/releasing.md), so
test here first. docs/hoon-testing.md is the case study behind the suites.

| | |
|---|---|
| set | `auspex` (in hoon-development's `fleet/sets.conf`) |
| ship | `~nep`, fake, pier `~/fleet/piers/nep` |
| HTTP | http://localhost:8123 (loopback in `~/fleet/piers/nep/.http.ports`) |
| dojo | `tmux attach -t fleet`, window `nep` |
| grubbery | the dev platform's pin (hoon-development `platform/grubbery.ref`) |
| auspex | a dev desk at `/apps/shell.shell/desks/auspex.desk`, the same path as on ricsul, following `/auspex-dev/code` in the ball; weir approved |
| test desk | `%auspex-test`, mounted, set up for the kit |

Below, `F=~/software/personal/hoon-development/fleet/fleet` and
`U=~/software/personal/hoon-development/bridge/u`. Set `FLEET_WHO` to
your session's name so claims know who is asking.

## Reset

```sh
$F reset auspex compiled   # auspex installed and approved, test desk set up: ~7 s
$F reset auspex            # golden: grubbery and %unix, no auspex
$F ls                      # is ~nep up?
$F up auspex               # restart it from its event log (vere 4.6 sometimes segfaults)
$F down auspex             # stop it when you are done
```

Start every test from `compiled`. Refresh it after a deploy that tests
should start from: `$F snap auspex compiled`. For a throwaway point,
`$F --fast snap auspex before-x` takes seconds.

## Offline tests (no ship)

```sh
scripts/offline-tests.sh     # auspex-web, 52 tests, ~22 s
python3 scripts/hoon-test-kit/offline-test.py tests/lib/auspex-web.hoon test-de-settings   # one arm
```

They run through `vere eval` with the kit's `offline-test.py`, which
reads `hoon-test.conf`: `/<` imports under `code/`, the `PRELUDE` faces
in every lib, and grubbery's own libs (`SHIP_FILES`) from a fleet pier's
mounted `%grubbery`. Only `auspex-web` runs offline. `auspex-chain`,
`auspex-vectors` and `auspex-fibers` all build `lib/auspex-chain`, which
signs with `cric:crypto` from kelvin 408's zuse; vere eval's own zuse
lacks it, so they stop at `-find.cric`. The ship run is the verdict.

## Ship tests

```sh
scripts/hoon-test-kit/hoon-test.sh ~/fleet/piers/nep               # all four suites, 213 tests, ~27 s
scripts/hoon-test-kit/hoon-test.sh ~/fleet/piers/nep auspex-chain  # one suite
```

chain 129, web 52, vectors 15, fibers 17. The kit finds vere in
`~/software`, so `VERE` need not be set. On a fresh set (golden, or a
rebuilt pier) make the test desk once: `|new-desk %auspex-test` and
`|mount %auspex-test` in the dojo, then
`scripts/hoon-test-kit/hoon-test.sh ~/fleet/piers/nep setup`.

The live route gate writes mail, so reset afterwards. It needs node:

```sh
scripts/hoon-test-kit/ship-cookie.sh ~/fleet/piers/nep http://localhost:8123 /tmp/nep.jar
node scripts/api-matrix.mjs http://localhost:8123 /tmp/nep.jar   # 15 checks, ~30 s
$F reset auspex compiled
```

`compiled` keeps the session the jar was minted for, so the jar works
after a reset. `~nep` signs with its own fake-ship keys (`whoami` says
`"keys":true`); no outside key is needed. `scripts/xship.mjs` and
`hoon-mutate.py --live` (LIVE_CHECK) need a second ship with auspex,
which this set does not have.

## Deploying a change to ~nep

```sh
scripts/dev-deploy.py http://localhost:8123 /tmp/nep.jar
```

It writes the files of `code/` that differ into `/auspex-dev/code` and
stamps that tree's `version.json` with a dev version, which makes the
desk pull. It refuses any ship that is not on localhost. A release that
adds a road needs approving again: `--approve` posts the instance's own
`weir.json` as `granted` to `/apps/grubbery/permits` (`approve-weir`),
then reloads its permits. For one file, `scripts/live-deploy.sh` (with
`AUSPEX_URL=http://localhost:8123`) writes straight into the desk.

How `compiled` was made, from the golden: `dev-deploy.py ... --add
--approve` (35 files, a few minutes), then the test desk.

## Looking inside with u

```sh
$U auspex our
$U auspex kids /auspex-dev/code
$U auspex kids /apps/shell.shell/desks/auspex.desk/desk/data/auspex.auspex_app
$U auspex file /apps/shell.shell/desks/auspex.desk/desk/code/version.json
```

`u` guards its subcommands. A raw `.^` in an expression that misses kills
every thread on the ship: check a path with `kids` first. Never point u,
the fleet commands or these scripts at a ship outside `auspex`.
