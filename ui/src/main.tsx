import { Component, StrictMode, type ReactNode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { whoami } from './api'

// THE LAST LINE BETWEEN ONE BAD RENDER AND A BLANK APPLICATION.
//
// React unmounts the entire tree when a render throws and nothing above
// it catches. Without a boundary that is not a broken pane, it is an
// empty <body>: no inbox, no error, no way to reach any other thread —
// and nothing on screen to say why, since the throw goes to a console
// nobody has open.
//
// That was not hypothetical. A thread whose every stored copy this build
// cannot read is served with an empty `messages`, ThreadView read
// `messages[0].subject` off it, and one click blanked the whole client.
// ThreadView guards that case now, but the class of failure is the
// problem: every field the nexus sends arrives inside a chain that any
// ship may deliver, and a client whose failure mode is "the application
// disappears" gives the next unguarded field the same reach. A boundary
// is the difference between a bug and an outage.
//
// A class component because that is the only thing React gives an error
// boundary; hooks have no equivalent.
class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  componentDidCatch(error: unknown, info: unknown) {
    // The console is the only place with the stack. Keep it, then say
    // something on screen too — that split is the whole point.
    console.error('urmail: render failed', error, info)
  }

  render() {
    if (!this.state.failed) return this.props.children
    // No retry button. The state that threw is still the state we would
    // re-render, so a retry would throw again and read as a broken
    // button; a reload refetches everything and is the honest offer.
    // Nothing here reads from the data that failed.
    return (
      <div className="p-8 text-neutral-800">
        <h1 className="mb-2 text-xl">Something in this view could not be displayed.</h1>
        <p className="mb-4 max-w-prose text-sm text-neutral-600">
          Your mail is unaffected — this is a display failure in the client, and
          nothing on the ship has changed. Reload to start again. If it happens
          on the same conversation every time, the browser console holds the
          detail.
        </p>
        <button
          type="button"
          onClick={() => { window.location.reload() }}
          className="rounded-full bg-blue-600 px-6 py-2 text-white hover:bg-blue-700"
        >
          Reload
        </button>
      </div>
    )
  }
}

const mount = () =>
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <ErrorBoundary>
        <App />
      </ErrorBoundary>
    </StrictMode>,
  )

// Our own @p comes from the nexus, and one component needs it the first
// time it renders: the reply composer drops us from its default recipient
// list, and seeding that list is a once-per-thread event that no later
// value can correct. So resolve it before the first paint rather than
// after — one same-origin request against a route the page was just
// served from.
//
// `.catch` and not `.finally` alone: if the ship cannot say who it is,
// the app still mounts (the inbox will render its own error) rather than
// showing a permanently blank page.
whoami().catch((e) => { console.error(e) }).then(mount)
