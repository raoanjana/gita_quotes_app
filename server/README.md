# Gita Quotes server

Anonymous usage analytics for the app, on AWS.

```
iPhone app ──HTTPS──▶ API Gateway ──▶ Lambda (checks events) ──▶ Firehose ──▶ S3 (one folder per day)
                                                                                  │
                                                         Athena (SQL queries) ◀───┘
```

- **What's collected:** app opens, verse views, explanation opens, share taps, widget taps (and which size), the Sanskrit switch, and short crash and hang summaries from MetricKit. Each comes with a random install ID made on the phone, the app version and the iOS version.
- **What isn't:** names, emails, Apple IDs, contacts, location, advertising IDs or IP addresses. Users can turn sharing off in the app's menu.
- **Cost:** with a few thousand daily users, expect well under $1 a month (Lambda, API Gateway and S3 have free tiers; Firehose is about 3¢ per GB). Built-in guards: a request rate limit, a 1 GB cap per Athena query, and an email alert if the month is forecast to pass your budget (default $10).
- **Later:** a DynamoDB table and Sign in with Apple can be added to this same template for saving user data.

Files:

| | |
|---|---|
| `template.yaml` | Everything AWS creates (AWS SAM format) |
| `src/events/app.py` | The function that checks and stores events |
| `tests/` | Tests for that function: `python3 -m unittest discover tests` |
| `tools/local_server.py` | A local stand-in for AWS, to test the app without deploying |
| `queries.sql` | Ready-made Athena queries (active users, top verses, retention…) |

## 1. Secure your AWS account (once, in the browser)

1. Sign in to the [AWS console](https://console.aws.amazon.com) as the root user (the email you signed up with).
2. **Turn on MFA for the root user:** account menu (top right) → *Security credentials* → *Assign MFA device*. Then avoid using the root user day to day.
3. **Create an everyday admin user with IAM Identity Center:**
   1. Open *IAM Identity Center* and choose *Enable*. Pick the region you'll use (for example `us-east-1`).
   2. *Users* → *Add user*: your name and email. Accept the email invitation and set a password and MFA.
   3. *AWS accounts* → select your account → *Assign users or groups* → your user → permission set *AdministratorAccess* (create it from the predefined list).
   4. Note the *AWS access portal URL* on the Identity Center dashboard (looks like `https://d-xxxxxxxxxx.awsapps.com/start`).

## 2. Install the tools on this Mac

```bash
brew install awscli aws-sam-cli
```

## 3. Sign in from this Mac

```bash
aws configure sso --profile gitaquotes
```

Enter the access portal URL and region from step 1. It opens the browser to approve. Then check it worked:

```bash
aws sts get-caller-identity --profile gitaquotes
```

Sign-ins last about 8–12 hours; renew with `aws sso login --profile gitaquotes`.

## 4. Deploy

From this `server` folder:

```bash
sam build && sam deploy --guided --profile gitaquotes
```

Answer: stack name `gitaquotes-analytics`, your region, **AlertEmail** = where cost alerts go, accept the other defaults, and save the answers (later deploys are just `sam build && sam deploy --profile gitaquotes`). AWS will email you once to confirm the budget alert.

At the end it prints **EventsEndpoint**. Put that URL in `App/Info.plist` (and `project.yml`) as `AnalyticsEndpoint`, rebuild the app, and events start flowing. They appear in S3 within about 5 minutes (Firehose batches them).

## 5. Look at the data

AWS console → *Athena* → workgroup **gitaquotes**, database **gitaquotes_analytics** → paste a query from `queries.sql`.

## Crashes and freezes

Two sources, both free:

- **Xcode Organizer** (no setup in the app). When you upload a build with Xcode (*Product → Archive → Distribute App*, keeping *Upload symbols* ticked), Apple symbolicates crash reports from TestFlight and App Store users who share analytics with developers. See them in Xcode → *Window → Organizer → Crashes*, grouped by cause, with the source line and how many people hit it. Reports appear after a day or two.
- **MetricKit → this server.** `App/CrashReports.swift` receives iOS's crash and hang reports the next time the app opens and sends each as a `crash` or `hang` event: exception type, signal, build, and the top of the call stack as `binary+0xoffset`. Query 9 in `queries.sql` lists them. To turn the app's frame into a source line, use the dSYM for that build (Xcode Organizer → *Archives* → the build → *Show in Finder* → right-click → *Show Package Contents* → `dSYMs`):

  ```bash
  atos -arch arm64 -o GitaQuotes.app.dSYM/Contents/Resources/DWARF/GitaQuotes -l 0x100000000 0x100001a2b
  ```

  where `0x1a2b` is the offset from `app_frame` added to the load address `0x100000000`. `app_uuid` tells you which build's dSYM to use (`dwarfdump --uuid` shows a dSYM's UUID).

MetricKit doesn't deliver reports for builds run from Xcode; to check the pipeline on a real iPhone, run the app from Xcode and choose *Debug → Simulate MetricKit Payloads*.

## Testing without AWS

```bash
python3 server/tools/local_server.py
xcrun simctl launch --terminate-running-process booted com.example.gitaquotes -AnalyticsEndpoint http://localhost:8787/v1/events
```

Use the app in the Simulator, then open http://localhost:8787 to see the events that arrived.

## Before App Store release

- Add a privacy policy URL in App Store Connect, saying what's collected (above) and that it's anonymous.
- App Privacy answers: *Usage Data → Product Interaction* and *Diagnostics → Crash Data, Performance Data*, all **not** linked to identity and **not** used for tracking. No App Tracking Transparency prompt is needed.
- Downloads, installs by country, and where installs came from are in App Store Connect → *Analytics*; this server only sees phones that open the app.
