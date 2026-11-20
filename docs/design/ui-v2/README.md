# School App Look & Feel — approved design (19 Nov 2026)

Reference mockups for the UI rebuild. Open any .dc.html as text: the markup holds the exact colours, spacing, radii and sizes; the script at the bottom holds the menu structure and sample data.

- Sidebar.dc.html — navy sidebar: brand block, "Find a page" search, standalone Dashboard link, 7 groups (all open by default, click to fold), active group tile orange, active item orange text + dot, user chip + sign out at the bottom. Drawer mode on phone has a close button.
- Main.dc.html — admin dashboard: top bar (breadcrumb, search, term chip, notifications), greeting + actions, 4 figure cards with progress bars, attendance this week, "needs your attention", fees by grade, coming up.
- Staff.dc.html — Staff page: tabs (All/Teaching/Non-teaching/Board & PA), search, table with Login status ("Can sign in"/"No login") and Access roles chips; action "Access roles" or "Invite to sign in".
- Phone.dc.html — phone: menu button, drawer from the left, dimmed backdrop that closes it.

Tokens: navy #0F1E3D (sidebar), navy-2 #1A2C52, line #22355E, orange #F26B1D (buttons/active, navy text on it), orange-light #FFB27A (text on navy), orange-tint #FFF1E7 / #9A3412, blue #1E3A8A (charts/links), page bg #F5F6FA, card #FFFFFF border #E6E9F1 radius 16, text #16213B, muted #5B6683, teal ok #E3F2EE/#0B5F55. Buttons/inputs 44px high, radius 12.
Font: use the OLD site's font (from frontend 745e978) — the user prefers it.
Names, numbers and the menu list are sample; use the real routes and real data.
