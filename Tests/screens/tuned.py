# Tuned on: everyday screenshots people take (all made up for these tests).
# ── Chats, plans and listings ─────────────────────────────────────────────────────
full("sunday-lunch-chat", [["lunch", "sunday"], ["plan", "chat", "message", "mom", "family"]], "sunday-lunch-plan", "Messages",
     window("Messages", chat("Mom", [
         (0, "Are you coming for lunch on Sunday?"),
         (1, "Yes! Around 1?"),
         (0, "Perfect. Bring the salad bowl back please 😄"),
         (1, "Will do, see you Sunday")]), w=620, h=560, x=400))
full("vet-checkup", [["vet", "veterinary"], ["checkup", "appointment", "visit", "biscuit"]], "vet-checkup-biscuit", "Calendar",
     window("Calendar", '<div style="border-left:5px solid #3a7bd5;padding-left:14px"><h2 style="margin:0">Vet checkup – Biscuit</h2>'
            '<p>Friday, 21 November 2026<br>16:00 – 16:30</p><p>📍 Riverside Animal Clinic</p><p><small>Bring vaccination card</small></p></div>',
            w=560, h=360, x=440, y=180))
full("pharmacy-ready", [["prescription", "pharmacy", "refill"]], "prescription-ready-for-pickup", "Safari",
     window("", '<h2 style="margin:0">Your prescription is ready</h2><p>Order #RX-55120 · Ready for pickup until 28 Nov</p>'
            '<p>Corner Pharmacy · 9 Mill Road</p><p><small>Bring a photo ID</small></p>',
            url="pharmacy.example.com/orders/rx-55120", w=900, h=480, x=260))
full("book-club", [["book", "club"], ["question", "notes", "midnight", "library"]], "book-club-questions", "Notes",
     window("Notes", '<h2 style="margin:0 0 10px">Book club – The Midnight Library</h2><div style="line-height:1.9">1. Which life would you pick?<br>'
            '2. Was the ending earned?<br>3. Favorite library scene<br>4. Next month: pick by Friday</div>',
            w=760, h=560, x=340, tbcolor="#f7f2d9"))
full("parking-citation", [["parking"], ["citation", "ticket", "fine"]], "parking-citation", "Safari",
     window("", '<h2 style="margin:0">Parking Citation #PC-208814</h2><p>Issued 12 Nov 2026 · Meter expired</p>'
            '<p>Amount due: <b>$45.00</b> by 12 Dec 2026</p><button>Pay now</button>',
            url="parking.example.gov/citations/PC-208814", w=900, h=440, x=260))
listing = lambda beds, extra, price, addr: window("", f'<div style="height:240px;background:linear-gradient(120deg,#c9d6b9,#e7d9c4);border-radius:8px"></div>'
            f'<h2 style="margin:12px 0 4px">{price}/mo</h2><div style="font-size:17px">{beds} · {extra}</div><div style="color:#555">{addr}</div>'
            '<p style="color:#0a66c2">Schedule a viewing · Message owner</p>', url="www.homefinder.example/listing/40517", w=1000, h=640, x=200)
full("house-listing", [["house", "home", "listing", "rent"], ["3", "three"]], "house-3-bed-linden-ave", "Safari",
     listing("3 bd · 2 ba house", "1,450 sqft · Garden", "$3,100", "42 Linden Ave, Portland, OR"))
full("studio-listing", [["studio", "apartment", "listing", "rent", "flat"]], "studio-apartment-elm-st", "Safari",
     listing("studio · 1 ba", "430 sqft · Laundry in building", "$1,650", "77 Elm St, Austin, TX"))

# ── Everyday screenshots people take ──────────────────────────────────────────────
full("recipe", [["cornbread"]], "hot-honey-cornbread", "Safari",
     window("", '<small>Recipes › Baking</small><h1 style="margin:6px 0">Hot Honey Skillet Cornbread</h1><p>Prep 10 min · Cook 25 min · Serves 8</p>'
            '<b>Ingredients</b><ul><li>1 cup yellow cornmeal</li><li>1 cup flour</li><li>3 tbsp hot honey</li><li>1 cup buttermilk</li></ul>',
            url="www.smittenbakes.com/hot-honey-cornbread", w=980, h=640, x=220))
full("boarding-pass", [["boarding", "flight", "pass"], ["ist", "istanbul", "lisbon", "lis", "tk1755", "turkish"]], "boarding-pass-ist-lis", "Wallet",
     window("Wallet", '<div style="background:#c8102e;color:#fff;border-radius:12px;padding:18px"><b>TURKISH AIRLINES</b> · Boarding Pass<h1 style="margin:10px 0">IST → LIS</h1>'
            'Flight TK1755 · 21 NOV 2026 · Boards 07:15 · Gate B12 · Seat 23A<br>Passenger: YILMAZ/DENIZ</div>', w=600, h=380, x=420, y=160))
full("tweet", [["vision", "pro", "apple", "tweet", "post"]], "tweet-vision-pro-price-cut", "Safari",
     window("", '<b>Mark Gurman</b> <small>@markgurman · 2h</small><p style="font-size:20px">Apple is planning a cheaper Vision Pro for 2027 with a lighter design and a starting price around $1,999, people familiar say.</p>'
            '<small>1.2K replies · 3.4K reposts · 18K likes</small>', url="x.com/markgurman/status/1855", w=760, h=420, x=340, y=140))
full("mac-error", [["open", "damaged", "error", "can't", "cant", "verify", "blocked", "malware"]], "app-cant-be-opened-error", "Finder",
     window("", '<div style="text-align:center;padding:20px"><div style="font-size:48px">⚠️</div><b>“PixelPad.app” Not Opened</b>'
            '<p>Apple could not verify “PixelPad.app” is free of malware that may harm your Mac or compromise your privacy.</p>'
            '<button>Done</button> <button>Move to Trash</button></div>', w=420, h=330, x=510, y=200))
full("xcode-error", [["build", "error", "fail", "compile"]], "build-error-cannot-find-usersession", "Xcode",
     window("Xcode", '<pre style="font-size:13px;background:#1e1e1e;color:#ddd;padding:14px;border-radius:6px">ProfileView.swift\n'
            '86   let user = UserSession.current\n<span style="color:#ff6b6b">⛔ Cannot find \'UserSession\' in scope</span>\n87   Text(user.name)</pre>'
            '<div style="color:#c00">Build Failed  |  1 error</div>', w=1000, h=520, x=200))
full("maps", [["direction", "route", "map", "drive", "walk"], ["airport", "sfo", "golden gate", "ferry"]], "directions-to-sfo", "Maps",
     window("Maps", '<div style="display:flex;gap:16px"><div style="width:300px"><h3>Directions</h3><p>From: Ferry Building<br>To: San Francisco International Airport (SFO)</p>'
            '<p><b>24 min</b> · 21.3 km via US-101 S</p></div><div style="flex:1;height:480px;background:linear-gradient(#cfe3c8,#e8eef3);border-radius:8px"></div></div>',
            w=1100, h=600, x=160))
full("bank-transfer", [["transfer", "payment", "sent", "receipt", "iban"]], "bank-transfer-receipt-rent", "Safari",
     window("", '<h2>Transfer completed ✓</h2><p>Amount: <b>₺18,500.00</b><br>To: Mehmet Kaya · TR12 0006 4000 0011 2345 6789 01<br>Description: November rent<br>Date: 03.11.2026 14:22</p>'
            '<small>Reference no: 7731902245</small>', url="internet.isbank.com.tr", w=820, h=480, x=300))
full("order-confirm", [["order", "purchase", "receipt"], ["headphone", "sony", "wh-1000", "xm6"]], "sony-headphones-order", "Safari",
     window("", '<h2>Thanks, your order is placed</h2><p>Order #112-4471937 · Arriving Tue, Nov 18</p><div style="display:flex;gap:14px"><div style="width:90px;height:90px;background:#222;border-radius:8px"></div>'
            '<div>Sony WH-1000XM6 Wireless Noise Canceling Headphones, Black<br><b>$399.99</b></div></div>', url="www.amazon.com/gp/buy/thankyou", w=900, h=480, x=260))
full("slack", [["deploy", "outage", "incident", "rollback", "api"]], "slack-api-deploy-rollback", "Slack",
     window("Slack", '<b># eng-backend</b><p><b>Deniz</b> <small>4:02 PM</small><br>Deploy v2.14 broke /checkout — 500s on 30% of requests</p>'
            '<p><b>Ece</b> <small>4:03 PM</small><br>Rolling back now. Incident channel: #inc-checkout</p><p><b>Deniz</b> <small>4:09 PM</small><br>Rollback done, error rate back to normal</p>',
            w=900, h=520, x=260, tbcolor="#3f0e40"))
full("wikipedia", [["byzantine", "constantinople", "hagia", "sophia"]], "hagia-sophia-wikipedia", "Safari",
     window("", '<h1 style="font-family:Georgia;font-weight:normal;border-bottom:1px solid #aaa">Hagia Sophia</h1><small>From Wikipedia, the free encyclopedia</small>'
            '<p>Hagia Sophia, officially the Hagia Sophia Grand Mosque, is a mosque and former church serving as a major cultural and historical site in Istanbul, Turkey. Built in 537 by the Byzantine emperor Justinian I...</p>',
            url="en.wikipedia.org/wiki/Hagia_Sophia", w=1000, h=560, x=200))
full("github-pr", [["pr", "pull", "request", "github"], ["dark", "mode"]], "pr-add-dark-mode", "Safari",
     window("", '<h2 style="font-weight:400">Add dark mode to settings screen <span style="color:#888">#482</span></h2><span style="background:#2da44e;color:#fff;padding:3px 10px;border-radius:12px">Open</span>'
            ' <small>ecek wants to merge 6 commits into main from ecek/dark-mode</small><p>✓ All checks have passed · 2 approvals</p>', url="github.com/orbit-labs/app/pull/482", w=1000, h=420, x=200, y=120))
full("weather", [["istanbul"], ["weather", "forecast", "rain"]], "istanbul-weather-forecast", "Weather",
     window("Weather", '<div style="text-align:center"><div style="font-size:30px">Istanbul</div><div style="font-size:80px;font-weight:200">12°</div><div>Rain · H:14° L:9°</div>'
            '<p style="color:#666">10-DAY FORECAST — Sat 13° · Sun 11° · Mon 15° · Tue 16°</p></div>', w=520, h=520, x=460, tbcolor="#5a7fa8"))
full("budget-sheet", [["budget"]], "monthly-budget-november", "Numbers",
     window("Numbers", '<h3>November Budget</h3><table border="1" cellpadding="6" style="border-collapse:collapse;font-size:14px"><tr><th>Category</th><th>Planned</th><th>Spent</th></tr>'
            '<tr><td>Rent</td><td>18,500</td><td>18,500</td></tr><tr><td>Groceries</td><td>4,000</td><td>3,215</td></tr><tr><td>Transport</td><td>1,200</td><td>960</td></tr><tr><td>Eating out</td><td>1,500</td><td>2,340</td></tr></table>',
            w=900, h=480, x=260))
full("job-email", [["interview", "offer", "invite"]], "stripe-interview-invite", "Mail",
     window("Mail", '<b>From:</b> Stripe Recruiting<br><b>Subject:</b> Interview invitation – Software Engineering Intern, Summer 2027<hr>'
            '<p>Hi Deniz,<br><br>Thanks for applying! We\'d love to invite you to a 45-minute technical interview. Please pick a time using the link below by November 21.</p>',
            w=1000, h=520, x=200))
full("concert-ticket", [["ticket", "concert"], ["coldplay", "concert"]], "coldplay-concert-ticket", "Wallet",
     window("Wallet", '<div style="background:#111;color:#fff;border-radius:12px;padding:18px"><small style="color:#aaa">ADMIT ONE</small><h1 style="margin:6px 0">Coldplay — Music of the Spheres</h1>'
            'Sat 6 Jun 2027 · 20:00 · Wembley Stadium, London<br>Block 112 · Row K · Seat 31</div>', w=640, h=320, x=400, y=180))
full("hotel", [["hotel", "booking", "reservation", "stay"]], "hotel-booking-lisbon", "Safari",
     window("", '<h2>Your booking is confirmed</h2><p><b>Hotel Lumen Lisboa</b> ★★★★<br>Check-in Fri 21 Nov 2026 · Check-out Mon 24 Nov 2026 · 3 nights<br>Confirmation: 4419.228.551</p><p>Total: €462</p>',
            url="secure.booking.com/confirmation", w=900, h=460, x=260))
full("dashboard", [["traffic", "analytics", "visitor", "dashboard", "user"]], "website-analytics-dashboard", "Safari",
     window("", '<h3>Analytics · Last 30 days</h3><div style="display:flex;gap:20px"><div><small>Visitors</small><h2>48,213</h2></div><div><small>Bounce rate</small><h2>41%</h2></div><div><small>Avg. visit</small><h2>2m 14s</h2></div></div>'
            '<div style="height:200px;background:linear-gradient(0deg,#dbeafe,#fff);border-bottom:2px solid #3b82f6"></div>', url="plausible.io/neatly.app", w=1000, h=520, x=200))
full("terminal-npm", [["npm", "install", "eresolve", "dependency", "error"]], "npm-install-error", "Terminal",
     window("Terminal", '<pre style="background:#111;color:#eee;padding:14px;font-size:13px">$ npm install\nnpm ERR! code ERESOLVE\nnpm ERR! ERESOLVE unable to resolve dependency tree\n'
            'npm ERR! Found: react@19.0.0\nnpm ERR! Could not resolve dependency:\nnpm ERR! peer react@"^18.0.0" from react-day-picker@8.10.1</pre>', w=900, h=360, x=260, y=160))
full("youtube", [["sourdough", "bread"]], "sourdough-video", "Safari",
     window("", '<div style="height:360px;background:#000;border-radius:10px"></div><h3>The Easiest Sourdough Bread for Beginners (No Mixer)</h3><small>Joshua Weissman · 2.1M views · 1 year ago</small>',
            url="www.youtube.com/watch?v=ab12cd", w=900, h=580, x=260))
full("course-schedule", [["schedule", "timetable", "course", "class"]], "fall-course-schedule", "Safari",
     window("", '<h3>Weekly Course Schedule — Fall 2026</h3><table border="1" cellpadding="6" style="border-collapse:collapse;font-size:13px"><tr><th></th><th>Mon</th><th>Tue</th><th>Wed</th><th>Thu</th></tr>'
            '<tr><td>09:40</td><td>CS 331</td><td></td><td>CS 331</td><td></td></tr><tr><td>13:40</td><td></td><td>CS 334</td><td></td><td>CS 334</td></tr><tr><td>15:40</td><td>MATH 260</td><td></td><td>MATH 260</td><td></td></tr></table>',
            url="student.northfield.edu/schedule", w=900, h=440, x=260))
full("tracking", [["track", "package", "shipment", "delivery", "parcel"]], "package-tracking", "Safari",
     window("", '<h2>Out for delivery</h2><p>Tracking number 1Z 999 AA1 01 2345 6784<br>Estimated delivery: Today by 8:00 PM</p><p>● Departed facility — Oakland, CA 5:12 AM<br>● Out for delivery 7:48 AM</p>',
            url="www.ups.com/track", w=840, h=440, x=280))
full("menu", [["menu"]], "restaurant-menu", "Safari",
     window("", '<h1 style="text-align:center;font-family:Georgia">Lokanta Maya · Dinner Menu</h1><p>Grilled octopus with fava purée — 640 ₺<br>Lamb shank, smoked eggplant — 890 ₺<br>'
            'Sea bass in parchment — 780 ₺<br>Pistachio semolina cake — 320 ₺</p>', url="lokantamaya.com/menu", w=900, h=480, x=260))
full("zoom-invite", [["zoom", "meeting", "call", "invite"]], "zoom-meeting-invite", "Mail",
     window("Mail", '<b>Subject:</b> Thesis check-in with Prof. Aydın<hr><p>Join Zoom Meeting<br>https://northfield.zoom.us/j/93812244710<br>Meeting ID: 938 1224 4710 · Passcode: 554210</p><p>Thursday Nov 20 · 15:00 Istanbul</p>',
            w=900, h=420, x=260, y=140))
full("product-page", [["air", "macbook", "laptop"]], "macbook-air-m5-price", "Safari",
     window("", '<div style="display:flex;gap:24px"><div style="width:380px;height:300px;background:#eee;border-radius:12px"></div><div><h1>MacBook Air 13″ (M5)</h1><p>10-core CPU · 16GB · 512GB SSD · Midnight</p>'
            '<h2>$1,299</h2><button>Add to Bag</button></div></div>', url="www.apple.com/shop/buy-mac/macbook-air", w=1000, h=480, x=200))
full("settings-wifi", [["wi-fi", "wifi", "network"]], "wifi-settings", "System Settings",
     window("System Settings", '<h2>Wi‑Fi</h2><p>Wi‑Fi <b style="float:right">On</b></p><p>✓ eduroam — Connected</p><p><small>Other networks</small><br>Northfield-Guest<br>Kahve Dünyası Free</p>',
            w=760, h=500, x=340))
full("quote-image", [["quote", "jobs", "stay", "hungry"]], "steve-jobs-stay-hungry-quote", "Preview",
     window("Preview", '<div style="background:#111;color:#fff;height:400px;display:flex;align-items:center;justify-content:center;flex-direction:column;font-family:Georgia">'
            '<div style="font-size:40px">“Stay hungry, stay foolish.”</div><div style="margin-top:14px">— Steve Jobs</div></div>', w=820, h=500, x=300))
full("calendar-week", [["week", "calendar", "schedule"]], "calendar-week", "Calendar",
     window("Calendar", '<h3>November 2026 · Week 47</h3><div style="display:grid;grid-template-columns:repeat(5,1fr);gap:6px;font-size:12px">' +
            "".join(f'<div style="background:#eef;padding:6px;height:200px"><b>{d}</b><br>{e}</div>' for d, e in
                    [("Mon 16", "Gym 08:00<br>CS 331"), ("Tue 17", "Standup 10:00"), ("Wed 18", "Thesis meeting"), ("Thu 19", "Haircut 10:30"), ("Fri 20", "Dinner w/ Ece")]) +
            '</div>', w=1100, h=420, x=160, y=120))
full("group-chat-dinner", [["dinner", "plan", "reservation", "saturday", "birthday"]], "birthday-dinner-plan", "WhatsApp",
     window("WhatsApp", chat("Ece's birthday 🎂", [(0, "So Saturday 8pm at Mikla?"), (0, "I booked for 6 people"), (1, "Perfect, I'll get the cake"), (0, "Don't tell her!!")]),
            w=620, h=560, x=400, tbcolor="#075e54"))

# Cmd-Shift-4 crops: just part of a window, no menu bar
only("crop-wifi-password", [["wifi", "wi-fi", "password", "network"]], "guest-wifi-password",
     '<div style="padding:30px;font-size:22px"><b>Guest Wi‑Fi</b><br>Network: CafeNero_Guest<br>Password: latte2026!</div>', 520, 200)
only("crop-flight-delay", [["delay", "flight", "delayed"]], "flight-delayed",
     '<div style="padding:24px;font-size:20px;background:#fff4e5"><b>TK1755 Istanbul → Lisbon</b><br><span style="color:#c00">Delayed · New departure 09:40</span><br>Gate B12</div>', 600, 180)
only("crop-meme-caption", [["monday", "coffee", "meme"]], "monday-coffee-meme",
     '<div style="background:#000;color:#fff;font:bold 36px Impact,sans-serif;text-align:center;padding:40px">ME ON MONDAY<br>BEFORE COFFEE</div><div style="height:200px;background:#776"></div>', 600, 380)

