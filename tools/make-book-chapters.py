from pathlib import Path
import argparse
import math
import re

import pymupdf
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

parser = argparse.ArgumentParser(description="Render the chapter-by-chapter book GIF.")
parser.add_argument("--preview-dir", type=Path, help="Optional directory for preview PNGs.")
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[1]
S = 768
PAPER = (248, 244, 233)
INK = (22, 39, 56)
MUTED = (80, 99, 112)
GOLD = (255, 198, 28)
TEAL = (0, 118, 126)
BG = (14, 22, 34)


def font(size, bold=False, serif=False):
    family = ("georgiab.ttf" if bold else "georgia.ttf") if serif else (
        "segoeuib.ttf" if bold else "segoeui.ttf"
    )
    return ImageFont.truetype(
        str(Path(r"C:\Windows\Fonts") / family), size
    )


def text(d, xy, value, size=24, fill=INK, bold=False, serif=False):
    assert xy[0] + d.textlength(value, font=font(size, bold, serif)) <= 740, value
    d.text(xy, value, font=font(size, bold, serif), fill=fill)


def wrapped(d, xy, value, size, width, fill=INK, bold=False, serif=False):
    lines = []
    for word in value.split():
        if not lines or d.textlength(lines[-1] + " " + word, font=font(size, bold, serif)) > width:
            lines.append(word)
        else:
            lines[-1] += " " + word
    for i, line in enumerate(lines):
        text(d, (xy[0], xy[1] + i * (size + 8)), line, size, fill, bold, serif)
    return xy[1] + len(lines) * (size + 8)


titles = {}
guide = (ROOT / "README.md").read_text(encoding="utf-8").split("## Chapter guide\n", 1)[1]
guide = guide.split("\n## ", 1)[0]
for line in guide.splitlines():
    match = re.match(r"\| (\d+) \| ([^|]+) \|", line)
    if match:
        titles[int(match[1])] = match[2].strip()
assert set(titles) == set(range(1, 12))
assert titles[1] == "Is It Hyper or Scale? Why Not Both?"
assert titles[10] == "Turbocharging and Optimizing Performance in Hyperscale"

# Short editorial highlights, grounded in the repository's chapter guide.
chapters = [
    ("Honoring Project Socrates.", ["SQL SERVER", "PROJECT SOCRATES", "HYPERSCALE"],
     ["Proven engine", "Distributed design", "Cloud-native SQL"],
     "How we built a new distributed, cloud-native SQL architecture."),
    ("Start small. Think big.", ["DEPLOY", "CONNECT", "BUILD"],
     ["Azure SQL", "Passwordless", "Synthetic data"],
     "Provision Hyperscale and bring Ward General to life."),
    ("Go inside the architecture.", ["COMPUTE", "LOG SERVICE", "PAGE SERVERS"],
     ["SQL + cache", "Log distribution", "Data pages"],
     "SQL Server engine + RBPEX. HA and named replicas."),
    ("Build something real.", ["HYPERSCALE", "BLAZOR", "PATIENT CHART"],
     ["SQL procedures", "Application", "Ward General"],
     "One hospital. One database. A working application."),
    ("Bring AI to your data.", ["EMBEDDINGS", "VECTOR SEARCH", "AI ASSISTANCE"],
     ["Meaning", "DiskANN index", "In-engine AI"],
     "Vectors + RAG in the SQL engine; governed calls via APIM."),
    ("Turn insight into action.", ["SQL MCP TOOLS", "HANDOFF AGENT", "APPROVAL"],
     ["Data API Builder", "Prepare handoff", "Gated save"],
     "Find candidates. Prepare a handoff. Approve the write."),
    ("See what the engine sees.", ["AZURE MONITOR", "QUERY STORE", "ENGINE EVENTS"],
     ["Service metrics", "Plans + runtime", "Extended Events"],
     "Database Hub, DMVs, and database agents."),
    ("Protect what matters.", ["ROW SECURITY", "AUDITING", "ENCRYPTION"],
     ["App identity", "Access evidence", "Optional TDE CMK"],
     "Apply security to the same Ward General application."),
    ("Prepare for the unexpected.", ["FAILOVER", "RESTORE", "GEO-REPLICA"],
     ["App retries", "Point in time", "Across regions"],
     "Built-in HA, geo-replication, and point-in-time restore."),
    ("Unleash the engine.", ["SCALE COMPUTE", "GROW DATA", "TUNE QUERIES"],
     ["8 / 16 / 40 / 192 vCores", "Write workload", "JSON + feedback"],
     "Serverless. Elastic pools. Smarter scaling and tuning."),
    ("Azure is the best cloud for SQL.", ["AZURE PLATFORM", "MIGRATION", "AI ECOSYSTEM"],
     ["Identity + Monitor", "Move to Hyperscale", "Microsoft Foundry"],
     "Change event streaming. Azure integration. Your AI future."),
]

with pymupdf.open(ROOT / "figures" / "book-cover.pdf") as pdf:
    pix = pdf[0].get_pixmap(matrix=pymupdf.Matrix(1.5, 1.5),
                          clip=pymupdf.Rect(606, 42, 1124, 791), alpha=False)
    cover = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)


def background():
    im = Image.new("RGB", (S, S), BG)
    d = ImageDraw.Draw(im)
    text(d, (44, 24), "AZURE SQL HYPERSCALE UNVEILED", 21, GOLD, True)
    text(d, (44, 730), "BOB WARD  /  APRESS", 17, (161, 180, 199), True)
    text(d, (506, 730), "TODAY + YOUR FUTURE", 16, (69, 215, 210), True)
    d.rounded_rectangle((28, 78, 740, 719), 10, fill=(5, 10, 18))
    d.rounded_rectangle((30, 72, 737, 713), 7, fill=(82, 53, 32))
    d.line((35, 83, 35, 700), fill=(142, 101, 57), width=2)
    for i in range(7):
        d.rounded_rectangle((43, 81 + i * 2, 733 - i, 710 - i * 2), 3,
                            fill=(211 + (i % 2) * 22, 207 + (i % 2) * 22, 195 + (i % 2) * 22))
    d.rectangle((39, 81, 44, 699), fill=(48, 33, 26))
    return im


def cover_page(closing=False):
    im = background()
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((44, 80, 724, 696), 5, fill=(28, 31, 36))
    thumb = cover.resize((265, 383), Image.Resampling.LANCZOS)
    im.paste(thumb, (70, 112))
    text(d, (366, 114), "HYPERSCALE:", 30, GOLD, True)
    for i, line in enumerate(["The cloud-native", "database for today", "and your future."]):
        text(d, (366, 169 + 42 * i), line, 27, PAPER, True)
    if closing:
        for i, line in enumerate(["Your next chapter", "starts here."]):
            text(d, (366, 354 + i * 40), line, 23, (69, 215, 210), True)
    else:
        wrapped(d, (366, 342), "Powered by SQL Server.",
                23, 326, (69, 215, 210), True)
        wrapped(d, (366, 418), "Cloud-native scale. AI built in.",
                21, 326, PAPER)
    text(d, (70, 506), "Architecture. Engine. Applications. AI. Azure.", 25, PAPER, True)
    text(d, (70, 536), "Book examples: AI-assisted creation and guided learning.", 17, (161, 180, 199))
    d.rounded_rectangle((70, 563, 700, 613), 10, fill=GOLD)
    text(d, (85, 575), "BOOK", 18, INK, True)
    text(d, (176, 568), "aka.ms/sqlhyperscaleunveiled", 28, INK, True)
    d.rounded_rectangle((70, 622, 700, 684), 10, outline=(69, 215, 210), width=2)
    text(d, (85, 634), "CODE", 18, (69, 215, 210), True)
    text(d, (176, 623), "aka.ms/sqlhyperscalebook", 26, PAPER, True)
    text(d, (176, 660), "github.com/rgward/sqlhyperscalebook", 16, (161, 180, 199))
    return im


ACCENTS = [
    (0, 118, 126), (0, 100, 170), (142, 78, 23), (0, 120, 142),
    (112, 66, 161), (67, 84, 163), (0, 110, 100), (41, 111, 65),
    (36, 96, 160), (166, 75, 25), (0, 112, 183),
]


def chapter_art(im, number, accent):
    d = ImageDraw.Draw(im)
    pale = tuple(round(c * 0.10 + 255 * 0.90) for c in accent)
    d.rounded_rectangle((80, 342, 690, 512), 12, fill=pale)

    def centered(x, y, value, size=18, color=INK, bold=True):
        width = d.textlength(value, font=font(size, bold))
        text(d, (x - width / 2, y), value, size, color, bold)

    def box(bounds, value, size=17, color=None):
        color = color or accent
        d.rounded_rectangle(bounds, 8, fill=color)
        centered((bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2 - size * 0.7,
                 value, size, PAPER)

    def arrow(points, color=None):
        color = color or accent
        d.line(points, fill=color, width=3)
        end, previous = points[-1], points[-2]
        angle = math.atan2(end[1] - previous[1], end[0] - previous[0])
        d.polygon([end] + [
            (end[0] - 9 * math.cos(angle + a), end[1] - 9 * math.sin(angle + a))
            for a in (-0.5, 0.5)
        ], fill=color)

    if number == 1:
        d.line((125, 404, 642, 404), fill=accent, width=4)
        for x, top, bottom in [(170, "SQL SERVER", "Proven engine"),
                               (385, "PROJECT SOCRATES", "Distributed design"),
                               (600, "HYPERSCALE", "Cloud-native SQL")]:
            d.ellipse((x - 12, 392, x + 12, 416), fill=accent)
            centered(x, 361, top, 17, accent)
            centered(x, 440, bottom, 17, INK, False)
        centered(385, 478, "Research. Engineering. A new architecture.", 17, accent)
    elif number == 2:
        d.rounded_rectangle((100, 356, 472, 496), 8, fill=INK)
        for i, value in enumerate(["> GitHub Copilot + skills",
                                   "> Provision Hyperscale", "> Connect with Entra ID",
                                   "> Build schema + seed data"]):
            text(d, (116, 363 + 31 * i), value, 19, (125, 235, 210))
        d.rectangle((533, 383, 648, 459), fill=accent)
        d.ellipse((533, 367, 648, 400), fill=(62, 151, 210))
        d.ellipse((533, 443, 648, 476), fill=accent)
        centered(590, 411, "SQL", 28, PAPER)
        arrow([(480, 424), (523, 424)])
    elif number == 3:
        read_color = (0, 111, 173)
        box((97, 351, 260, 391), "PRIMARY", 17)
        box((308, 351, 463, 391), "HA REPLICAS", 16)
        box((495, 351, 675, 391), "NAMED REPLICAS", 16)
        box((105, 431, 285, 469), "LOG SERVICE", 17)
        box((344, 431, 496, 469), "PAGE SERVERS", 15)
        box((541, 431, 675, 469), "AZURE STORAGE", 13)
        arrow([(178, 391), (178, 431)])
        arrow([(285, 450), (320, 450), (320, 409), (385, 409), (385, 391)])
        arrow([(320, 409), (585, 409), (585, 391)])
        arrow([(285, 450), (344, 450)])
        arrow([(496, 450), (541, 450)])
        arrow([(240, 391), (240, 419), (365, 419), (365, 431)], read_color)
        arrow([(440, 391), (440, 431)], read_color)
        arrow([(510, 391), (510, 443), (496, 443)], read_color)
        centered(385, 477, "Blue: page reads from primary, HA, and named replicas", 15, read_color)
        centered(385, 497, "Brown: log write / redo and durable storage paths", 14, accent)
    elif number == 4:
        with Image.open(ROOT / "figures" / "ch04-first-app" /
                        "ch04-fig-01-the-digital-chart-application.png") as screenshot:
            # Focus on the Unit board rather than spending thumbnail space on navigation.
            left = round(screenshot.width * 0.17)
            top = round(screenshot.height * 0.07)
            right = round(screenshot.width * 0.99)
            bottom = top + round((right - left) * 154 / 390)
            preview = screenshot.crop((left, top, right, bottom))
            preview.thumbnail((390, 154), Image.Resampling.LANCZOS)
            im.paste(preview, (92, 350))
        box((480, 366, 674, 411), "BLAZOR + SQL")
        text(d, (493, 430), "Ward General", 22, accent, True)
        text(d, (493, 463), "The working app", 17, MUTED)
    elif number == 5:
        d.rounded_rectangle((97, 350, 524, 503), 10, outline=accent, width=2)
        text(d, (112, 357), "INSIDE THE SQL ENGINE", 18, accent, True)
        box((112, 391, 283, 431), "VECTORS + DiskANN", 15)
        box((323, 391, 507, 431), "RETRIEVE + PROMPT", 15)
        arrow([(283, 411), (323, 411)])
        box((550, 391, 676, 431), "APIM", 18)
        arrow([(507, 411), (550, 411)])
        box((550, 456, 676, 493), "FOUNDRY", 16)
        arrow([(613, 431), (613, 456)])
        arrow([(613, 456), (613, 431)])
        arrow([(550, 411), (507, 411)])
        box((344, 456, 507, 493), "AI ASSISTANCE", 15)
        arrow([(415, 431), (415, 456)])
        embedding_color = (0, 111, 173)
        embedding_path = [(198, 431), (198, 448), (535, 448), (535, 487), (550, 487)]
        arrow(embedding_path, embedding_color)
        arrow(list(reversed(embedding_path)), embedding_color)
        text(d, (211, 432), "Embeddings: direct", 12, embedding_color, True)
        text(d, (112, 461), "In-engine RAG", 19, accent, True)
        text(d, (112, 485), "Models stay external", 14, MUTED)
        centered(613, 358, "AI GATEWAY", 15, accent)
    elif number == 6:
        box((101, 366, 261, 414), "SQL MCP TOOLS")
        box((316, 366, 484, 414), "HANDOFF AGENT")
        arrow([(261, 390), (316, 390)])
        d.polygon([(578, 357), (635, 390), (578, 423), (521, 390)], fill=accent)
        centered(578, 376, "Approve?", 16, PAPER)
        arrow([(484, 390), (521, 390)])
        arrow([(578, 423), (578, 457)])
        box((497, 458, 662, 498), "SAVE HANDOFF", 16)
        text(d, (110, 450), "Draft a patient handoff.", 20, accent, True)
        text(d, (110, 481), "A human stays in the loop.", 17, MUTED)
    elif number == 7:
        d.line((110, 363, 110, 478, 430, 478), fill=MUTED, width=2)
        d.line([(110, 463), (150, 449), (182, 456), (219, 387), (244, 420),
                (278, 371), (314, 433), (355, 414), (395, 453), (430, 445)], fill=accent, width=4)
        for i, label in enumerate([
            "DATABASE HUB", "AZURE MONITOR", "DMVs", "QUERY STORE",
            "ENGINE EVENTS", "DATABASE AGENTS",
        ]):
            y = 350 + 27 * i
            box((457, y, 674, y + 24), label, 14)
    elif number == 8:
        d.polygon([(192, 355), (264, 377), (257, 444), (227, 478),
                   (192, 499), (157, 478), (127, 444), (120, 377)], fill=accent)
        d.line((157, 424, 183, 451, 228, 398), fill=PAPER, width=9)
        for i, label in enumerate(["ROW-LEVEL SECURITY", "AUDIT ACCESS", "ENCRYPT DATA"]):
            y = 357 + i * 50
            d.ellipse((318, y + 8, 337, y + 27), fill=accent)
            text(d, (355, y + 2), label, 21, accent, True)
    elif number == 9:
        for x in (283, 486):
            d.line((x, 361, x, 491), fill=(187, 205, 222), width=1)
        centered(182, 355, "BUILT-IN HA", 18, accent)
        box((99, 396, 178, 431), "PRIMARY", 13)
        box((207, 396, 264, 431), "HA", 16)
        arrow([(178, 413), (207, 413)])
        centered(182, 451, "Primary + HA replicas", 15, accent, False)
        centered(182, 479, "Failover + app retries", 14, MUTED, False)
        centered(385, 355, "GEO-REPLICATION", 17, accent)
        for x in (329, 439):
            d.ellipse((x - 24, 389, x + 24, 437), outline=accent, width=2)
            d.ellipse((x - 12, 389, x + 12, 437), outline=accent, width=1)
            d.line((x - 24, 413, x + 24, 413), fill=accent, width=1)
        arrow([(358, 413), (410, 413)])
        centered(385, 451, "Across regions", 15, accent, False)
        centered(385, 479, "Geo-secondary", 14, MUTED, False)
        centered(588, 355, "PITR", 18, accent)
        d.ellipse((557, 382, 619, 444), outline=accent, width=3)
        d.line((588, 392, 588, 413, 571, 422), fill=accent, width=3)
        for angle in range(0, 360, 90):
            radians = math.radians(angle)
            x, y = 588 + 25 * math.cos(radians), 413 + 25 * math.sin(radians)
            d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=accent)
        centered(588, 451, "Point-in-time restore", 15, accent, False)
        centered(588, 479, "Recover a test copy", 14, MUTED, False)
    elif number == 10:
        for x, height, label in [(105, 24, "8"), (173, 48, "16"),
                                 (241, 74, "40"), (309, 115, "192")]:
            d.rounded_rectangle((x, 480 - height, x + 48, 480), 5, fill=accent)
            centered(x + 24, 483, label, 16, accent)
        centered(232, 354, "vCORE SCALING", 16, accent)
        for i, label in enumerate([
            "SERVERLESS", "ELASTIC POOLS", "OPTIMIZED LOCKING",
            "AUTOMATIC INDEX COMPACTION", "JSON INDEXES", "MEMORY GRANT FEEDBACK",
        ]):
            y = 350 + i * 27
            box((390, y, 675, y + 24), label, 14)
    elif number == 11:
        center = (385, 425)
        for bounds, label in [((100, 352, 282, 394), "ENTRA ID"),
                              ((488, 352, 672, 394), "MONITOR"),
                              ((100, 458, 260, 500), "MIGRATION"),
                              ((510, 458, 672, 500), "FOUNDRY AI")]:
            mid = ((bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2)
            d.line((center, mid), fill=accent, width=3)
            box(bounds, label)
        d.ellipse((321, 363, 449, 465), fill=accent)
        centered(385, 377, "AZURE SQL", 18, PAPER)
        centered(385, 412, "HYPERSCALE", 16, PAPER)
        arrow([(385, 465), (385, 478)])
        box((272, 478, 498, 506), "CHANGE EVENT STREAMING", 14)


def chapter_page(number):
    im = background()
    d = ImageDraw.Draw(im)
    d.rectangle((44, 80, 724, 696), fill=PAPER)
    for x in range(44, 65):
        shade = round(209 + (x - 44) / 20 * 39)
        d.line((x, 80, x, 696), fill=(shade, shade - 3, shade - 12))
    accent = ACCENTS[number - 1]
    d.rectangle((80, 108, 147, 113), fill=accent)
    text(d, (164, 96), f"CHAPTER {number:02d}", 21, accent, True)
    end = wrapped(d, (80, 143), titles[number], 32, 602, bold=True, serif=True)
    assert end <= 280, (number, end)
    hero, labels, details, takeaway = chapters[number - 1]
    wrapped(d, (80, 286), hero, 26, 602, accent, serif=True)
    chapter_art(im, number, accent)
    wrapped(d, (80, 535), takeaway, 24, 602, serif=True)
    d.line((80, 646, 690, 646), fill=(200, 204, 199), width=1)
    text(d, (80, 660), "AZURE SQL HYPERSCALE UNVEILED", 15, MUTED, True)
    text(d, (603, 657), f"{number:02d} / 11", 18, TEAL, True)
    return im


def turn(old, new, progress):
    im = new.copy()
    # A slanted, bowed fold exposes the next page; the translucent reverse
    # retains a hint of mirrored ink instead of becoming an opaque wipe.
    bend = math.sin(math.pi * progress)
    edge = 724 - 680 * (0.5 - 0.5 * math.cos(math.pi * progress))
    reverse = ImageOps.mirror(old)
    reverse = Image.blend(reverse, Image.new("RGB", old.size, PAPER), 0.92)
    for y in range(80, 696):
        fraction = (y - 80) / 616
        bow = math.sin(math.pi * fraction)
        left = round(max(44, min(724, edge + bend * (46 * (1 - 2 * fraction) - 28 * bow))))
        width = max(1, round(bend * (110 + 44 * bow)))
        right = min(724, left + width)
        im.paste(old.crop((44, y, left, y + 1)), (44, y))
        if right <= left:
            continue
        # The shadow falls on the exposed page, following the paper's curve.
        shadow_end = min(724, right + round(25 * bend))
        if shadow_end > right:
            shadow = im.crop((right, y, shadow_end, y + 1))
            shade = Image.new("RGB", shadow.size)
            sd = ImageDraw.Draw(shade)
            for x in range(shadow.width):
                value = round(160 + 95 * x / shadow.width)
                sd.point((x, 0), fill=(value, value, value))
            im.paste(ImageChops.multiply(shadow, shade), (right, y))
        strip = reverse.crop((max(44, left - 150), y, max(45, left), y + 1))
        strip = strip.resize((right - left, 1), Image.Resampling.BICUBIC)
        light = Image.new("RGB", strip.size)
        ld = ImageDraw.Draw(light)
        for x in range(strip.width):
            position = x / max(1, strip.width - 1)
            value = round(192 + 63 * math.sin(math.pi * position) ** 0.7)
            ld.point((x, 0), fill=(value, value, value))
        im.paste(ImageChops.multiply(strip, light), (left, y))
    return im


def summary_page():
    im = background()
    d = ImageDraw.Draw(im)
    d.rectangle((44, 80, 724, 696), fill=PAPER)
    d.rectangle((80, 108, 147, 113), fill=TEAL)
    text(d, (164, 96), "THE STORY CONTINUES", 21, TEAL, True)
    wrapped(d, (80, 143), "Build once. Evolve with confidence.", 36, 590,
            bold=True, serif=True)
    text(d, (80, 254), "Scale independently. Keep familiar SQL.", 23, TEAL, serif=True)
    text(d, (80, 289), "Grow into AI. Stay on one platform.", 23, TEAL, serif=True)
    text(d, (80, 337), "FROM CHAPTER 11 / QUOTE EXCERPT", 16, MUTED, True)
    quote = (
        '"Customers can begin with what they need today and expand over time '
        'without redesigning the application or moving to a different platform. '
        'That freedom to build once and evolve with confidence makes Hyperscale '
        'a critical part of Microsoft\u2019s database strategy."'
    )
    end = wrapped(d, (96, 371), quote, 23, 574, serif=True)
    assert end <= 588, end
    d.line((80, 376, 80, end - 6), fill=TEAL, width=3)
    text(d, (96, 594), "Arun Ulag", 22, INK, True, serif=True)
    text(d, (96, 625), "Vice President of Azure", 17, MUTED)
    d.line((80, 657, 690, 657), fill=(200, 204, 199), width=1)
    text(d, (80, 668), "YOUR DATABASE NOW AND FOR THE FUTURE", 15, TEAL, True)
    return im


pages = ([cover_page()] + [chapter_page(i) for i in range(1, 12)]
         + [summary_page(), cover_page(True)])
frames = [pages[0]]
delays = [12000]
for index in range(1, len(pages)):
    for step in range(1, 13):
        frames.append(turn(pages[index - 1], pages[index], step / 13))
        delays.append(80)
    frames.append(pages[index])
    delays.append(14000 if index == len(pages) - 2 else 6000)
palette_sheet = Image.new("RGB", (S * len(pages), S))
for i, page in enumerate(pages):
    palette_sheet.paste(page, (i * S, 0))
palette = palette_sheet.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
output = ROOT / "figures" / "book-chapters.gif"
indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=delays,
                loop=0, optimize=True, disposal=1)
with Image.open(output) as gif:
    total = 0
    for frame in range(gif.n_frames):
        gif.seek(frame)
        total += gif.info["duration"]
        gif.load()
    assert gif.size == (S, S) and gif.info["loop"] == 0
    assert total == sum(delays)
    assert delays[13::13] == [6000] * 11 + [14000, 6000]
    assert total == 110480
    assert output.stat().st_size < 10_000_000
    print(f"Verified: 11 chapters, {gif.n_frames} frames, {total / 1000:.2f}s, "
          f"{output.stat().st_size:,} bytes, infinite loop; all frames decoded.")
if args.preview_dir:
    args.preview_dir.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGB", (384 * 4, 384 * 4), BG)
    for i, page in enumerate(pages):
        sheet.paste(page.resize((384, 384)), ((i % 4) * 384, (i // 4) * 384))
    sheet.save(args.preview_dir / "chapter-promo-storyboard.png")
    frames[6].save(args.preview_dir / "chapter-page-turn-preview.png")
print(output)
