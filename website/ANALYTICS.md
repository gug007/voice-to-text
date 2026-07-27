# VoiceToText search and analytics operations

This runbook covers the account-side work recommended after the July 2026 organic-search review. It documents the changes but does not authorize making them automatically.

## Property identifiers

- GA4 account: `391874904`
- GA4 property: `533722037`
- Web measurement ID used by the site: `G-6XX9WSS0TH`
- Search Console property: `sc-domain:voicetotext.cc`
- Reporting window: last 28 complete days, compared with the preceding 28 days

Before changing a setting, use the account and property selectors to verify these identifiers. Linking requires at least Editor access to the GA4 property and verified-owner access to the Search Console property.

## Link Search Console to GA4

1. Open GA4 property `533722037`.
2. Select **Admin**.
3. Under **Product links**, select **Search Console links**.
4. Select **Link**.
5. In **Link to Search Console properties I manage**, select **Choose accounts**.
6. Select `sc-domain:voicetotext.cc`, then select **Confirm**.
7. Select **Next**.
8. Select the `voicetotext.cc` web data stream and verify that it uses `G-6XX9WSS0TH`.
9. Select **Next**, review all three identifiers, then select **Submit**.

A Search Console property can be linked to only one GA4 web stream, and the link cannot be edited. A wrong link must be deleted and recreated. Google documents the current flow and limits in [Connect Search Console to Google Analytics](https://support.google.com/analytics/answer/10737381).

The Search Console report collection is unpublished by default:

1. In GA4, open **Reports** and then **Library**.
2. Find the **Search Console** collection.
3. Open its collection menu and select **Publish**.
4. Confirm that **Search Console → Queries** and **Search Console → Google organic search traffic** now appear in report navigation.

Allow up to 48 hours for the latest Search Console data to appear. The integration can report at most the 16 months retained by Search Console.

## Verify the two site events

The website already emits the following exact event names:

- `download_click`, with `placement`, `event_label`, and `link_url` when available
- `demo_start`, with `placement` plus either `event_label`/`autoplay` for the product video or `source` for the interactive dictation demo

Do not create renamed copies in GA4. Event names are case-sensitive.

To verify collection:

1. Open **Reports → Realtime** in one tab.
2. In a private browser window with analytics blocking disabled, load `https://voicetotext.cc/`.
3. Play the product demo once.
4. Open one download link in a new tab.
5. In Realtime, confirm that both `demo_start` and `download_click` appear in **Event count by Event name**.
6. Repeat on one guide page to confirm that page and event attribution are preserved outside the homepage.

Realtime usually updates within minutes. The normal Events list and standard reports can take up to 24 hours. DebugView only shows devices sending debug-mode events; connect the test browser with [Tag Assistant](https://tagassistant.google.com/) before using **Admin → Data display → DebugView** for event-order details.

## Use `download_click` as the primary outcome

GA4 has a binary key-event flag; it does not have GA4-level “primary” and “secondary” priorities. Implement the requested hierarchy as follows:

- `download_click`: mark as a key event and treat it as the primary website outcome in reports.
- `demo_start`: keep as a regular event and label it as a secondary engagement signal in dashboards.

For an event GA4 has already received:

1. Open **Admin → Data display → Events**.
2. On **Recent events**, search for `download_click`.
3. Select the star beside `download_click` to mark it as a key event.
4. Leave the default **Once per event** counting method. Use **Session key event rate** in acquisition reports so repeat clicks do not inflate the reported conversion rate.
5. Search for `demo_start` and confirm that its star is off. If it is already a key event, clear the star; this does not remove the event itself.

If `download_click` has not reached the Events list yet:

1. Open **Admin → Data display → Key events**.
2. Select **New key event**.
3. Enter exactly `download_click` and save it.

This pre-marks the event the existing website code will send; it does not require a GA4-created derivative event. Key-event reporting begins from the time the event is marked and is not retroactive. See [Mark events as key events](https://support.google.com/analytics/answer/13128484).

“Primary” and “Secondary” are also Google Ads conversion-action optimization settings, but that is a separate feature. Do not create or import an Ads conversion unless paid-campaign bidding is actually in scope.

## Investigate landing page `(not set)`

For the Landing page dimension, Google says `(not set)` normally means that the session did not contain a `page_view` event. Historical values cannot be repaired; diagnose and fix future collection.

### Isolate the affected sessions

1. Open **Explore** and create a **Free form** exploration.
2. Set the date to the last 28 complete days. If a historical comparison is needed, clone the exploration and set the clone to the preceding 28 complete days; Explorations do not provide the standard-report comparison toggle.
3. Import these dimensions:
   - `Landing page + query string`
   - `Event name`
   - `Session source / medium`
   - `Hostname`
   - `Page location`
   - `Date`
   - `Device category`
   - `Browser`
4. Import these metrics:
   - `Sessions`
   - `Active users`
   - `Engaged sessions`
   - `Event count`
5. Add a filter where `Landing page + query string` exactly matches `(not set)`.
6. Start with `Event name` as rows, `Session source / medium` as columns, and `Event count` plus `Sessions` as values.
7. Make duplicate tabs that replace rows with `Hostname`, `Date`, `Device category`, and `Browser`.

Interpret the result:

- If the affected sessions contain `session_start` or interaction events but no `page_view`, page-view collection or event order is the problem.
- A blank or unexpected hostname suggests events are reaching this property from outside `voicetotext.cc`.
- A single-day spike suggests a deployment or tag outage; a browser/device concentration suggests blocking or compatibility behavior.
- If most rows are tied to one referral source, reproduce the exact landing flow from that source before changing the tag.

### Reproduce page-view collection

1. Open **Admin → Data streams**, select the `G-6XX9WSS0TH` web stream, and inspect **Enhanced measurement**.
2. Confirm **Page views** is enabled. In its advanced settings, confirm browser-history changes are measured so Next.js client-side navigation produces page views.
3. With Realtime open, test:
   - a fresh load of `/`;
   - a fresh load of every indexable landing page;
   - navigation between pages using internal links;
   - `demo_start`;
   - a `download_click`.
4. For event order and parameters, connect the browser through Tag Assistant, open DebugView, and confirm that each fresh session sends `session_start` and a first `page_view` before the interaction event. Confirm that `page_location` contains the expected canonical URL.
5. Check the browser Network panel for requests to Google Analytics if Realtime and the debug-enabled device show nothing. Repeat with extensions disabled.
6. If full loads work but client-side navigation does not, either keep browser-history page views enabled or add explicit route-change page views in the site. Do not enable both if they produce duplicate page views.
7. Record the fix date and monitor the `(not set)` share for the next 28 days.

Google's current explanation of the affected dimensions is [What the value “(not set)” means](https://support.google.com/analytics/answer/13504892).

## Recommended 28-day SEO dashboard

Always show **Last 28 complete days** with **Compare: preceding period**. Keep query reporting and onsite behavior in separate panels because Search Console query dimensions are not compatible with most GA4 behavior dimensions.

### 1. Search visibility scorecards

Use the linked Search Console data:

- Organic Google search clicks
- Organic Google search impressions
- Organic Google search click-through rate
- Organic Google search average position

Show the absolute value and percentage change from the preceding 28 days for each metric.

### 2. Query opportunity table

Use **Organic Google search query** as the primary dimension. Allow `Country` and `Device category` as drill-down dimensions. Add:

- Organic Google search impressions
- Organic Google search clicks
- Organic Google search click-through rate
- Organic Google search average position

Sort first by impressions. Create a saved view for high-impression queries with zero or low clicks, then inspect those queries by position rather than treating CTR alone as the problem. The compatible dimensions and metrics are documented in [Queries report](https://support.google.com/analytics/answer/13682862).

### 3. Landing-page search and engagement table

Use **Landing page + query string** as the primary dimension. Allow `Country` and `Device category` as drill-down dimensions. Add:

- Organic Google search clicks
- Organic Google search impressions
- Organic Google search click-through rate
- Organic Google search average position
- Active users
- Engaged sessions
- Engagement rate
- Average engagement time
- Event count
- Key events

This table connects search visibility to post-click quality without combining incompatible query and behavior dimensions. See [Google organic search traffic report](https://support.google.com/analytics/answer/13682863).

### 4. Google-organic outcome table

Create a separate GA4 Free form exploration with a session filter:

- `Session source` exactly matches `google`
- `Session medium` exactly matches `organic`

Use `Landing page + query string` as rows and add:

- Sessions
- Active users
- Engaged sessions
- Engagement rate
- Average engagement time per session
- Key events
- Session key event rate

Because `download_click` is the only custom event marked as a key event, Key events and Session key event rate represent the primary download outcome. If other key events are added later, select or filter to `download_click` explicitly.

Add a second event-detail tab with `Event name` as rows, limited to `download_click` and `demo_start`, and show:

- Event count
- Active users
- Event count per active user

Label `download_click` **Primary outcome** and `demo_start` **Secondary engagement** in the dashboard. Break out `download_click` by `placement` only after `placement` has been registered as an event-scoped custom dimension; custom dimensions are not retroactive.

## Weekly review rules

- Review the dashboard once per week, but make SEO decisions on the full 28-day window.
- Compare CTR only for similar average-position ranges and the same device/country mix.
- Prioritize pages and queries already receiving impressions in positions 4–20.
- Record title, description, and major content changes with their deployment dates.
- Run one snippet test per page at a time and leave it in place for at least four weeks unless it causes a clear regression.
- Report download intent using `download_click` Session key event rate; report `demo_start` separately and never combine it with downloads as a single conversion count.
