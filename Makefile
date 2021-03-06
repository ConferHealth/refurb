
.PHONY: build clean update-build refurb.cabal

build: update-build
	stack test --no-interleaved-output

clean:
	stack clean

update-build: package.nix

package.nix: refurb.cabal
	rm -f package.nix
	nix-shell -p haskellPackages.cabal2nix --run 'cabal2nix .' > package.nix

refurb.cabal:
	nix-shell -p haskellPackages.hpack --run 'hpack'
