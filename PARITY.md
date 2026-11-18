# Feature parity with the official Mattermost mobile app

Audited against the source of `mattermost/mattermost-mobile` (commit `3992834`, 2026-11-17): every directory under
`app/screens` and the user-facing ones under `app/components`. Each row names the official code it was ported from.

Status: ✅ ported · 🟡 partly ported (what's missing is stated) · ❌ not ported · ⏭ left out on purpose.

**Verification:** everything marked ✅/🟡 compiles. Rows tagged *(seen)* were also exercised in the simulator on
2026-11-17; the rest were ported from code and have **not been run yet**.

## Screens (`app/screens`)

| Official screen | What it is | Status | Ours |
|---|---|---|---|
| `home/tab_bar` | Bottom tabs: Home, Search, Mentions, Saved, Account; indicator bar; mention badge | ✅ | `HomeTabsViewController` |
| `home/channel_list` | Team header, + menu, unread filter, Find channels field, categories | ✅ *(seen)* | `ChannelListViewController` |
| `home/channel_list/…/plus_menu` | Browse Channels, Create New Channel, Open a Direct Message | 🟡 no "Invite people" | `showPlusMenu` |
| `home/channel_list/servers` | Multiple servers | ⏭ | |
| `home/search` | Search field, search options, recent searches, Messages/Files results | 🟡 no from:/in: autocomplete, no file-type filter | `SearchViewController` |
| `home/recent_mentions` | Recent Mentions | ✅ | `PostResultsViewController.mentions` |
| `home/saved_messages` | Saved Messages | ✅ | `PostResultsViewController.saved` |
| `home/account` | Avatar, status, custom status, Your Profile, Settings, Log out | ✅ | `AccountViewController` |
| `channel` | Channel screen: header, post list, composer | ✅ *(seen, before header/composer rework)* | `ConversationViewController` |
| `channel/header` | Title, DM avatar + status, custom status / member count, quick actions | 🟡 no bookmarks bar | `setUpHeader` |
| `channel/channel_post_list/intro` | "Beginning of…" intro | ✅ | `ChannelIntroCell` |
| `thread` | Thread screen with reply composer and Follow button | ✅ *(seen, before rework)* | `ConversationViewController(rootId:)` |
| `global_threads` | Threads: All / Unreads, mark all read, thread options | ✅ | `ThreadsListViewController` |
| `thread_options` | Open in channel, mark read, unfollow, copy link | 🟡 as a context menu; no Save | `ThreadsListViewController` |
| `global_drafts` | Drafts list | 🟡 no scheduled tab | `DraftsViewController` |
| `post_options` | Long-press sheet: reaction bar + actions | ✅ *(seen)* | `PostOptionsViewController` |
| `emoji_picker` | Emoji picker | 🟡 redesigned (half sheet, category bar); no skin-tone picker | `EmojiPickerViewController` |
| `reactions` | Who reacted | ✅ | `ReactionsViewController` |
| `edit_post` | Edit a message | 🟡 text only (no attachment editing) | `EditPostViewController` |
| `permalink` | Message + context, "Jump to recent messages" | 🟡 no "join channel to view" flow | `PermalinkViewController` |
| `pinned_messages` | Pinned Messages | ✅ | `PostResultsViewController.pinned` |
| `channel_files` | Channel files | 🟡 no type filter | `FileListViewController` |
| `gallery` | Image viewer: zoom, swipe, save, share; video | 🟡 video uses the system player; no copy-public-link | `GalleryViewController`, `VideoPlayer` |
| `pdf_viewer`, document preview | PDFs and documents | ✅ via QuickLook | `FilePreviewer` |
| `attachment_options` | Photo library, camera, files | ✅ | `showAttachmentOptions` |
| `find_channels` | Find Channels | ✅ | `FindChannelsViewController` |
| `browse_channels` | Browse / join public channels | 🟡 no archived/shared filter | `BrowseChannelsViewController` |
| `create_or_edit_channel` | New channel, edit name/purpose/header | ✅ | `CreateChannelViewController` |
| `create_direct_message` | New DM / group message | ✅ | `CreateDirectMessageViewController` |
| `channel_info` | Info, favorite, mute, notifications, pinned, files, members, leave, archive | 🟡 no convert-to-private, no auto-follow threads | `ChannelInfoViewController` |
| `channel_notification_preferences` | Per-channel mobile notifications | 🟡 push level + ignore @channel only | in `ChannelInfoViewController` |
| `manage_channel_members` | Members list | 🟡 view + profile; no role change / remove | `MembersViewController` |
| `channel_add_members` | Add members | ✅ | `AddMembersViewController` |
| `user_profile` | Profile sheet, Send message | ✅ | `UserProfileViewController` |
| `edit_profile` | Your Profile | 🟡 no photo change | `EditProfileViewController` |
| `custom_status`, `custom_status_clear_after` | Custom status with suggestions and expiry | 🟡 no custom date/time, no recents | `CustomStatusViewController` |
| `settings` | Settings root | ✅ | `SettingsViewController` |
| `settings/notification_*` | Mentions, push, thread replies, email, auto-reply | 🟡 simplified; no test notification | `NotificationSettingsViewController` |
| `settings/display_*` | Theme, clock, timezone, collapsed threads | 🟡 timezone is read-only | `DisplaySettingsViewController` |
| `settings/advanced` | Delete local files | ✅ | `AdvancedSettingsViewController` |
| `settings/about` | About | ✅ | `AboutViewController` |
| `login`, `mfa` | Login, MFA | ✅ restyled to match *(old styling seen)* | `LoginViewController` |
| `forgot_password` | Reset password | 🟡 opens the web page | |
| `in_app_notification` | Banner for a DM/mention elsewhere | ✅ | `InAppNotificationView` |
| `snack_bar` | Toasts | ✅ *(seen)* | `showToast` |
| `bottom_sheet` | Option sheets | ✅ *(seen)* | `PostOptionsViewController` |
| `code`, `table` | Full-screen code / table | ❌ | |
| `select_team`, `join_team` | Teams | ⏭ one team | |
| `server`, `edit_server`, `sso`, `onboarding` | Server picker, SSO | ⏭ | |
| `channel_bookmark`, `channel_settings`, `channel_configuration`, `channel_share`, `convert_gm_to_channel` | Channel admin extras | ⏭ | |
| `invite` | Invite people | ❌ | |
| `apps_form`, `dialog_router`, `integration_selector`, `mm_blocks_content` | Interactive dialogs / apps | ⏭ | |
| `draft_scheduled_post_options`, `scheduled_post_options`, `reschedule_draft`, `post_priority_picker` | Scheduled posts, priority | ⏭ | |
| `latex`, `show_translation`, `report_a_problem`, `review_app`, `share_feedback`, `terms_of_service`, `data_erased`, `watermark`, `component_library` | Misc | ⏭ | |

## Post rendering (`app/components/post_list`, `markdown`, `files`)

| Official code | Feature | Status |
|---|---|---|
| `post/header` | Avatar, name, BOT tag, time (12/24h pref) | ✅ *(seen)* |
| `post/pre_header` | "Pinned" / "Saved" line and tinted background | ✅ |
| `post/body/message` | Markdown: emphasis, strike, headings, lists, quotes, links, code | ✅ *(seen)* |
| `markdown_code_block`, `syntax_highlight` | Code blocks with highlighting | 🟡 generic highlighter, not per-language; no full-screen view |
| `markdown_table` | Tables | 🟡 rows with separators, not a grid |
| `markdown_image` | Inline images | ✅ shown under the text |
| `at_mention`, `channel_mention`, `hashtag` | Tappable @mention → profile, ~channel → channel, #tag → search | ✅ |
| `components/emoji`, `jumbo_emoji` | `:emoji:`, custom emoji, jumbo | ✅ *(standard seen; custom not yet seen)* |
| `content/opengraph`, `youtube` | Link previews | 🟡 card with image; no inline YouTube player |
| `content/image_preview`, `files` | Image / video previews, file cards | ✅ *(images seen)* |
| audio files | Inline play/pause for voice notes | 🟡 no scrubber or speed |
| `content/message_attachments` | Bot attachments incl. images | ✅ *(text seen)*; buttons/menus ⏭ |
| `content/permalink_preview` | Preview of a linked message | ❌ (link opens the permalink screen) |
| `body/reactions` | Reaction chips, toggle, add, long-press → who reacted | ✅ *(toggle seen)* |
| `post/footer` | Reply count, Following | 🟡 no participant avatars |
| `body/failed` | Failed send: Retry / Delete | ✅ |
| `edited_indicator` | "Edited" | ✅ |
| `date_separator`, `new_message_line` | Separators | ✅ *(seen)* |
| `more_messages` | Jump to recent button | 🟡 no unread count |
| `show_more_button` | Collapse very long posts | ❌ |
| `post_draft/typing` | "x is typing…" (shown and sent) | ✅ |
| `system_message` | System messages | 🟡 server text, not re-templated |
| `post_priority`, `acknowledgements`, `burn_on_read`, LaTeX | | ⏭ |

## Composer (`app/components/post_draft`, `autocomplete`)

| Official code | Feature | Status |
|---|---|---|
| `draft_input`, `send_button` | Input box, send button | ✅ *(seen)* |
| `quick_actions` | Attach, @, /, emoji | ✅ |
| `autocomplete/at_mention` | @users, @here/@channel/@all | ✅ |
| `autocomplete/channel_mention` | ~channels | ✅ |
| `autocomplete/emoji_suggestion` | :emoji: incl. custom | ✅ |
| `autocomplete/slash_suggestion` | /commands + execute | 🟡 no app-command parser |
| `uploads` | Upload strip with progress, remove; paste images | ✅ |
| `draft_handler` | Drafts synced with the server | ✅ |
| `archived`, `read_only` | Archived channel notice | 🟡 archived only |
| hardware keyboard | Return sends | ✅ |

## Sidebar details (`components/channel_item`, `threads_button`, `drafts_buttton`)

| Feature | Status |
|---|---|
| Channel rows, DM avatars + status, mention badge, muted, active row | ✅ *(seen)* |
| Draft pencil on rows, Threads row with unread badge, Drafts row | ✅ |
| Collapse category (synced), unreads filter, "Unreads" category preference | ✅ *(collapse and filter seen)* |
| Long-press channel → Favorite, Mute, Add members, Copy link, Info, Leave/Close | ✅ |

## Sync and notifications

| Feature | Status |
|---|---|
| WebSocket: posts, edits, deletes, reactions, typing, statuses, threads, drafts, categories, users, emoji | ✅ *(posts seen)* |
| Reconnect and catch-up; connection indicator (a spinner in the sidebar header instead of a banner) | ✅ |
| Local cache: instant launch, read offline (sidebar + latest page per channel) | 🟡 JSON files, not a full database; older pages aren't cached |
| App icon badge = mentions | ✅ |
| Push registration, notification extension, inline reply | ✅ needs your own push relay (docs/NOTIFICATIONS.md) |
| Clear notifications when read elsewhere | ✅ (WebSocket + silent "clear" push) |
| iPhone Duo: on the inner screen a thread opens full width, sliding the channel list away | ✅ |

## Not ported, by choice
Calls, Playbooks, Boards, AI agents, channel bookmarks, scheduled posts, message priority, burn-on-read, LaTeX,
multi-server, SSO, guest accounts, interactive message buttons/menus and app dialogs.

## Still to do
1. Run every unverified row above on iPhone 17 and iPhone Duo and fix what breaks.
2. `show_more_button`, `permalink_preview`, full-screen code/table, participant avatars on thread footers.
3. Audio scrubber and speed, emoji skin tones, profile photo change, member role management, invite people.
4. Search autocomplete for `from:` / `in:`.
