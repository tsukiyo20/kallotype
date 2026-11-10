/// What the window looks like around the app.
///
/// `mac` means the system's title bar is hidden and the content runs to the
/// top edge: the traffic lights sit over the sidebar, and the toolbar is the
/// drag handle. It is pinned rather than read from `Platform` at the point of
/// use, so a golden can draw the same window anywhere.
enum WindowChrome {
  /// The system draws a title bar above the app.
  plain,

  /// No title bar; traffic lights over the sidebar, toolbar drags the window.
  mac,
}
