Jacquard on the Web
===================

A Web build of [Jacquard], a prototype grid sequencer, served from the root of this
repository by GitHub Pages:

**https://www.keijiro.tokyo/jacquard-web/**

That is the address rather than `keijiro.github.io/jacquard-web/` because the account
carries a custom domain, and a project site inherits it. The `github.io` one still
works: it answers with a redirect here.

Nothing here is written by hand. It is the output of a Unity 6.5 (6000.5.6f1) Web
build, and the only reason it is a repository of its own is that GitHub Pages serves
what a repository contains rather than what a build produces.

Built from [Jacquard] at `510c609`.

Sound
-----

The Scriptable Audio Pipeline the synth normally runs on is not supported on the Web,
so this build renders the same DSP from `Update` and pushes it to the Web Audio API
instead. That costs about 110ms before a note can sound; the sequence itself is
unaffected.

Audio will not start until the page has been clicked, which every browser insists on.
Pressing Play is enough.

`.nojekyll` is here so that Pages serves the files as they are.

[Jacquard]: https://github.com/keijiro/Jacquard
