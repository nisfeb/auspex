# Grubbery update: Lattice and Auspex are moving

**What's changing**

Until now, Lattice shipped *inside* Grubbery — its code was part of the
Grubbery desk itself. With this update it becomes an app that Grubbery installs
and keeps up to date on its own, alongside Auspex, both distributed from
`~ricsul-bilwyt`. Your Landscape tile will say **Grubbery** and open the
launcher; Lattice and Auspex live inside it.

**Nothing is deleted.** Your pages, memories and bookmarks are copied to the
new location. The old copy stays exactly where it was.

**What happens on your ship**

The update arrives through the normal Grubbery sync. When it lands, Grubbery
will:

1. set up the Lattice and Auspex apps automatically — no action needed
2. ask you for permission to run them — **this is the one thing you have to do**

Until you grant those permissions, Lattice is unavailable, and if you use it as
an AI memory store the tools will report an empty vault rather than an error.
Nothing is lost; it's waiting on you.

**Your action items, once the update lands**

1. Open Grubbery. The bell in the top corner will show a count. Open it.
2. You'll see two items: **lattice wants permissions** and **auspex wants
   permissions**. Click **Review** on each.
3. On the permissions page, approve each app's requested roads. They're the
   same things Lattice always did — serve your pages, keep your memory, talk to
   other ships.
4. That's it. Lattice copies your data across within a few seconds of the
   first approval and is back at its usual address.

If the bell is empty and the apps are still unavailable, open
`/apps/grubbery/permits` directly.

**If you'd rather wait**

The update is being released to `~ricsul-bilwyt` first and to everyone else a
day or two later. If you'd like to hold it back on your ship until you're
ready, tell Grubbery to stop following the source:

```
|pause %grubbery
```

Nothing changes on your ship while paused. When you're ready:

```
|install ~ricsul-bilwyt %grubbery
```

resumes following, and the update arrives normally.

**Questions**

Ask in the usual place. If something looks wrong after you've approved both
apps, say what the bell and the permissions page show — that's what we'll
need.
