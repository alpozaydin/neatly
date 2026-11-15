# Held-out screenshots: written after tuning, never used to tune. Everyday screens.
full("h-landlord-chat", [["heating", "heater", "boiler", "radiator", "repair"]], "heating-repair-chat", "Messages",
     window("Messages", chat("Landlord – Mr. Demir", [(1, "Hi, the heating stopped working again since last night"), (0, "I'll send the technician tomorrow between 10 and 12"), (1, "Thank you, it's really cold"), (0, "He will call before coming")]), w=620, h=560, x=400))
full("h-grocery-list", [["grocery", "groceries", "shopping"]], "grocery-list", "Reminders",
     window("Reminders", '<h2 style="color:#e8463c">Groceries</h2><div style="line-height:2">○ Eggs<br>○ Oat milk<br>○ Spinach<br>○ Lemons<br>○ Coffee beans<br>○ Toilet paper</div>', w=600, h=520, x=420, tbcolor="#fafafa"))
full("h-haircut", [["haircut", "barber", "hair"]], "haircut-appointment", "Calendar",
     window("Calendar", '<div style="border-left:5px solid #a259ff;padding-left:14px"><h2 style="margin:0">Haircut</h2><p>Saturday, 22 November 2026<br>14:00 – 14:45</p><p>📍 Kuaför Murat, Bahçelievler</p></div>', w=560, h=320, x=440, y=180))
full("h-pizza-order", [["pizza", "domino"], ["order", "delivery", "receipt"]], "dominos-pizza-order", "Safari",
     window("", '<h2>Your order is on its way! 🛵</h2><p>Domino\'s Pizza · Order #55120<br>1 × Large Pepperoni<br>1 × Garlic Bread<br>Total: ₺689</p><p>Estimated arrival 20:35</p>', url="www.dominos.com.tr/siparis-takip", w=880, h=460, x=280))
full("h-car-listing", [["car", "golf", "volkswagen", "vw"]], "volkswagen-golf-for-sale", "Safari",
     window("", '<div style="height:220px;background:linear-gradient(120deg,#ccd,#eef);border-radius:8px"></div><h2>2019 Volkswagen Golf 1.5 TSI Highline</h2><p>₺1,250,000 · 68,000 km · Automatic · Petrol</p><p>Kadıköy, İstanbul</p>', url="www.sahibinden.com/ilan/vasita-otomobil", w=980, h=600, x=220))
full("h-train-ticket", [["train", "rail", "yht"], ["ticket", "izmir", "istanbul", "booking"]], "izmir-istanbul-train-ticket", "Safari",
     window("", '<h2>E-Ticket · High Speed Train</h2><p><b>Izmir → İstanbul (Pendik)</b><br>Fri 28 Nov 2026 · 09:10 – 13:05<br>Coach 4 · Seat 12A · Economy</p>', url="ebilet.tcddtasimacilik.gov.tr", w=860, h=420, x=290, y=140))
full("h-vpn-error", [["vpn", "connect", "connection"]], "vpn-connection-failed", "System Settings",
     window("", '<div style="text-align:center;padding:20px"><div style="font-size:42px">⚠️</div><b>VPN Connection Failed</b><p>The L2TP-VPN server did not respond. Try reconnecting. If the problem continues, verify your settings and contact your Administrator.</p><button>OK</button></div>', w=440, h=320, x=500, y=200))
full("h-python-error", [["python", "keyerror", "traceback", "error"]], "python-keyerror", "Terminal",
     window("Terminal", '<pre style="background:#111;color:#eee;padding:14px;font-size:13px">$ python train.py\nTraceback (most recent call last):\n  File "train.py", line 42, in &lt;module&gt;\n    lr = config["learning_rate"]\nKeyError: \'learning_rate\'</pre>', w=880, h=340, x=280, y=160))
full("h-news-article", [["earthquake", "quake"]], "earthquake-news", "Safari",
     window("", '<small>WORLD · 3 hours ago</small><h1 style="font-family:Georgia">Magnitude 6.1 earthquake strikes off Crete, felt in Athens</h1><p>No casualties were reported after the quake hit at a depth of 10 km, the Greek civil protection agency said.</p>', url="www.reuters.com/world/europe", w=1000, h=480, x=200))
full("h-paper-abstract", [["diffusion", "segmentation", "medical"]], "medical-diffusion-segmentation-paper", "Safari",
     window("", '<small>arXiv:2611.04412 [cs.CV]</small><h2>MedDiff-Seg: Diffusion Priors for Few-Shot Medical Image Segmentation</h2><p><b>Abstract.</b> We propose a diffusion-based prior for segmenting organs from CT with only five labelled scans...</p>', url="arxiv.org/abs/2611.04412", w=1000, h=460, x=200))
full("h-gym-schedule", [["gym", "class", "yoga", "pilates", "fitness"]], "gym-class-schedule", "Safari",
     window("", '<h2>MACFit Class Schedule</h2><table border="1" cellpadding="6" style="border-collapse:collapse"><tr><th>Mon</th><th>Wed</th><th>Fri</th></tr><tr><td>Yoga 08:00</td><td>Pilates 18:30</td><td>Spinning 19:00</td></tr></table>', url="www.macfit.com.tr/dersler", w=820, h=380, x=310, y=160))
full("h-electric-bill", [["electric", "electricity", "enerjisa", "power"]], "electricity-bill", "Safari",
     window("", '<h2>Enerjisa · Electricity Bill</h2><p>Period: October 2026<br>Consumption: 212 kWh<br>Amount due: ₺1,184.50<br>Due date: 25.11.2026</p>', url="online.enerjisa.com.tr/fatura", w=820, h=420, x=310))
full("h-podcast", [["podcast", "huberman", "sleep"]], "huberman-sleep-podcast", "Podcasts",
     window("Podcasts", '<div style="display:flex;gap:16px"><div style="width:160px;height:160px;background:#333;border-radius:10px"></div><div><small>Huberman Lab</small><h2>Master Your Sleep & Be More Alert When Awake</h2><p>1 hr 52 min · Episode 2</p></div></div>', w=900, h=360, x=260, y=160))
full("h-airbnb", [["airbnb", "cabin", "stay", "booking", "reservation"]], "cappadocia-cabin-airbnb", "Safari",
     window("", '<h2>Cave Suite with Valley View · Göreme</h2><p>Entire cave house · 2 guests · 1 bedroom<br>★ 4.96 · 212 reviews</p><p>Dec 19 – 22 · €284 total</p><button>Reserve</button>', url="www.airbnb.com/rooms/7712", w=960, h=440, x=240))
full("h-figma", [["onboarding", "design", "mockup", "figma"]], "onboarding-design-figma", "Figma",
     window("Figma", '<small>Drafts / Neatly</small><div style="display:flex;gap:16px;margin-top:10px">' + "".join(f'<div style="width:180px;height:340px;border:1px solid #ccc;border-radius:16px;padding:10px"><b>Onboarding {i}</b><p style="font-size:12px">{t}</p></div>' for i, t in [(1, "Welcome to neatly"), (2, "Name your downloads"), (3, "You are all set")]) + '</div>', w=1000, h=520, x=200, tbcolor="#2c2c2c"))
full("h-stock", [["nvidia", "nvda", "stock"]], "nvidia-stock", "Stocks",
     window("Stocks", '<h2>NVDA · NVIDIA Corporation</h2><div style="font-size:40px">$187.42 <span style="color:#2a2;font-size:20px">+3.1%</span></div><div style="height:180px;background:linear-gradient(0deg,#dfd,#fff);border-bottom:2px solid #2a2"></div>', w=820, h=440, x=310))
full("h-lecture-slide", [["dijkstra", "shortest", "path", "graph"]], "dijkstra-shortest-path-slide", "Keynote",
     window("Keynote", '<div style="background:#fff;border:1px solid #ddd;height:420px;padding:30px"><h1>Dijkstra\'s Algorithm</h1><ul style="font-size:20px"><li>Single-source shortest paths</li><li>Non-negative edge weights</li><li>O((V + E) log V) with a binary heap</li></ul></div>', w=1000, h=540, x=200))
full("h-lost-cat", [["cat", "lost", "missing"]], "lost-cat-poster", "Preview",
     window("Preview", '<div style="text-align:center;background:#ffeb3b;padding:20px;height:420px"><h1 style="font-size:54px;margin:0">LOST CAT</h1><div style="width:200px;height:160px;background:#888;margin:10px auto"></div><p style="font-size:20px">Grey tabby "Pamuk" · Moda, Kadıköy<br>Call 0532 000 00 00</p></div>', w=600, h=540, x=420))
only("h-crop-2fa", [["code", "verification", "2fa", "login"]], "verification-code",
     '<div style="padding:26px;font-size:20px">Your Instagram verification code is <b>482 913</b>. Don\'t share it.</div>', 700, 120)
only("h-crop-address", [["address", "location", "office"]], "office-address",
     '<div style="padding:26px;font-size:20px"><b>Our office</b><br>Maslak Mah. Büyükdere Cd. No:255<br>Sarıyer, İstanbul 34398</div>', 560, 180)
