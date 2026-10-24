from pathlib import Path
import argparse
from functools import lru_cache
import math
import re
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFont, ImageOps

parser = argparse.ArgumentParser(description="Render the chapter-by-chapter book GIF.")
parser.add_argument("--preview-dir", type=Path, help="Optional directory for preview PNGs.")
parser.add_argument("--landscape", action="store_true", help="Show the physical book on a 16:9 canvas.")
parser.add_argument("--frames-dir", type=Path, help="Export PNG frames and a video timing manifest.")
# Accept the former version flag while making the approved open-book layout the default.
parser.add_argument("--v2", action="store_true", default=True, help=argparse.SUPPRESS)
args = parser.parse_args()
if args.landscape and not args.frames_dir:
    parser.error("--landscape requires --frames-dir")
ROOT = Path(__file__).resolve().parents[1]
S = 768
W = 1366 if args.landscape else S
PAPER = (255, 255, 255)
INK = (22, 39, 56)
MUTED = (80, 99, 112)
GOLD = (255, 198, 28)
TEAL = (0, 118, 126)
BG = (14, 22, 34)
BOOK_URL = "aka.ms/sqlhyperscaleunveiled"
GIF_SIZE = 640
GIF_COLORS = 96
GIF_MAX_BYTES = 5_000_000
SUMMARY_SUBTITLE = "Hyperscale is your database now and for the future."
BOOK_DEDICATION = (
    "This book is dedicated to all at Microsoft who spent countless hours "
    "to take Project Socrates from a dream to the reality that is "
    "Azure SQL Hyperscale today."
)
QUOTE_CONTRIBUTORS = (
    "Shireesh Thota", "Slava Oks", "Krystyna Reisteter", "Anna Hoffman",
    "Kendal Van Dyke", "Naveen Prakash", "Arun Ulag",
)
ARUN_QUOTE = (
    '"Customers can begin with what they need today and expand over time '
    'without redesigning the application or moving to a different platform. '
    'That freedom to build once and evolve with confidence makes Hyperscale '
    'a critical part of Microsoft\u2019s database strategy."'
)


def font(size, bold=False, serif=False):
    family = ("georgiab.ttf" if bold else "georgia.ttf") if serif else (
        "segoeuib.ttf" if bold else "segoeui.ttf"
    )
    return ImageFont.truetype(
        str(Path(r"C:\Windows\Fonts") / family), size
    )


class ScaledDraw:
    """Draw in layout coordinates without raster-upscaling text or shapes."""

    def __init__(self, image, scale=1):
        self.draw = ImageDraw.Draw(image)
        self.scale = scale
        self.width = image.width / scale

    def coordinates(self, values):
        return [self.coordinates(value) if isinstance(value, (tuple, list))
                else value * self.scale for value in values]

    def text(self, xy, value, font, **kwargs):
        self.draw.text(self.coordinates(xy), value,
                       font=font.font_variant(size=round(font.size * self.scale)), **kwargs)

    def textlength(self, value, font):
        return self.draw.textlength(
            value, font=font.font_variant(size=round(font.size * self.scale))
        ) / self.scale

    def shape(self, name, xy, **kwargs):
        if "width" in kwargs:
            kwargs["width"] = max(1, round(kwargs["width"] * self.scale))
        getattr(self.draw, name)(self.coordinates(xy), **kwargs)

    def line(self, xy, **kwargs):
        self.shape("line", xy, **kwargs)

    def rectangle(self, xy, **kwargs):
        self.shape("rectangle", xy, **kwargs)

    def ellipse(self, xy, **kwargs):
        self.shape("ellipse", xy, **kwargs)

    def polygon(self, xy, **kwargs):
        self.shape("polygon", xy, **kwargs)

    def rounded_rectangle(self, xy, radius, **kwargs):
        self.shape("rounded_rectangle", xy, radius=radius * self.scale, **kwargs)


def text(d, xy, value, size=24, fill=INK, bold=False, serif=False):
    assert xy[0] + d.textlength(value, font=font(size, bold, serif)) <= getattr(d, "width", W) - 28, value
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
     "An app-hosted agent uses an LLM and SQL MCP; you approve the save."),
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
    ("Azure is the best cloud for SQL.", ["AZURE", "MICROSOFT FOUNDRY", "MIGRATE"],
     ["Azure App Service", "Change Event Streaming", "Fabric Mirroring"],
     "Azure. Microsoft Foundry. Migrate. Azure App Service. "
     "Change Event Streaming. Fabric Mirroring."),
]

with Image.open(ROOT / "figures" / "book-cover.png") as image:
    cover = image.convert("RGB")


@lru_cache(maxsize=8)
def azure_sql_database_icon(size):
    with Image.open(ROOT / "figures" / "icons" / "azure-sql-database.png") as icon:
        return icon.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)


def background(scale=1):
    im = Image.new("RGB", (round(W * scale), round(S * scale)), PAPER)
    d = ScaledDraw(im, scale)
    text(d, (44, 24), "AZURE SQL HYPERSCALE UNVEILED", 18, MUTED, serif=True)
    d.line((44, 60, W - 44, 60), fill=(217, 222, 224), width=1)
    text(d, (44, 730), "BOB WARD  /  APRESS", 15, MUTED)
    text(d, (W - 262, 730), "TODAY + YOUR FUTURE", 15, MUTED)
    return im


def cover_page(closing=False):
    im = background()
    d = ImageDraw.Draw(im)
    if args.landscape:
        im.paste(cover.resize((330, 477), Image.Resampling.LANCZOS), (100, 110))
        text(d, (500, 105), "HYPERSCALE:", 36, TEAL, True, serif=True)
        wrapped(d, (500, 166), "The cloud-native database for today and your future.",
                42, 745, INK, True, serif=True)
        if closing:
            text(d, (500, 317), "Your next chapter starts here.", 32, TEAL, serif=True)
        else:
            text(d, (500, 317), "Powered by SQL Server.", 32, TEAL, serif=True)
            text(d, (500, 367), "Cloud-native scale. AI built in.", 28, INK, serif=True)
        text(d, (500, 440), "Architecture. Engine. Applications. AI. Azure.", 27, INK, serif=True)
        text(d, (500, 486), "Book examples: AI-assisted creation and guided learning.", 20, MUTED)
        text(d, (500, 549), "BOOK", 18, TEAL, True)
        text(d, (595, 539), "aka.ms/sqlhyperscaleunveiled", 31, INK, True)
        text(d, (500, 610), "CODE", 18, TEAL, True)
        text(d, (595, 600), "aka.ms/sqlhyperscalebook", 31, INK, True)
        text(d, (595, 646), "github.com/rgward/sqlhyperscalebook", 19, MUTED)
        return im
    thumb = cover.resize((265, 383), Image.Resampling.LANCZOS)
    im.paste(thumb, (70, 112))
    text(d, (366, 114), "HYPERSCALE:", 30, TEAL, True, serif=True)
    for i, line in enumerate(["The cloud-native", "database for today", "and your future."]):
        text(d, (366, 169 + 42 * i), line, 27, INK, True, serif=True)
    if closing:
        for i, line in enumerate(["Your next chapter", "starts here."]):
            text(d, (366, 354 + i * 40), line, 23, TEAL, serif=True)
    else:
        wrapped(d, (366, 342), "Powered by SQL Server.",
                23, 326, TEAL, True, serif=True)
        wrapped(d, (366, 418), "Cloud-native scale. AI built in.",
                21, 326, INK, serif=True)
    text(d, (70, 506), "Architecture. Engine. Applications. AI. Azure.", 24, INK, serif=True)
    text(d, (70, 536), "Book examples: AI-assisted creation and guided learning.", 17, MUTED)
    d.rounded_rectangle((70, 563, 700, 613), 10, fill=GOLD)
    text(d, (85, 575), "BOOK", 18, INK, True)
    text(d, (176, 568), "aka.ms/sqlhyperscaleunveiled", 28, INK, True)
    d.rounded_rectangle((70, 622, 700, 684), 10, outline=(207, 218, 220), width=1)
    text(d, (85, 634), "CODE", 18, TEAL, True)
    text(d, (176, 623), "aka.ms/sqlhyperscalebook", 26, INK, True)
    text(d, (176, 660), "github.com/rgward/sqlhyperscalebook", 16, MUTED)
    return im


ACCENTS = [
    (0, 118, 126), (0, 100, 170), (142, 78, 23), (0, 120, 142),
    (112, 66, 161), (67, 84, 163), (0, 110, 100), (41, 111, 65),
    (36, 96, 160), (166, 75, 25), (0, 112, 183),
]


def architecture_art(accent, scale=1):
    pale = tuple(round(c * 0.10 + 255 * 0.90) for c in accent)
    im = Image.new("RGB", (1200 * scale, 360 * scale), PAPER)
    d = ScaledDraw(im, scale)
    d.rounded_rectangle((0, 0, 1199, 359), 18, fill=pale)
    log_color = (0, 117, 103)
    read_color = (0, 111, 173)

    def arrow(points, color):
        d.line(points, fill=color, width=4)
        end, previous = points[-1], points[-2]
        angle = math.atan2(end[1] - previous[1], end[0] - previous[0])
        d.polygon([end] + [
            (end[0] - 12 * math.cos(angle + a), end[1] - 12 * math.sin(angle + a))
            for a in (-0.5, 0.5)
        ], fill=color)

    for bounds, label in [
        ((40, 10, 310, 65), "PRIMARY"),
        ((460, 10, 730, 65), "HA REPLICAS"),
        ((880, 10, 1150, 65), "NAMED REPLICAS"),
        ((40, 150, 310, 210), "LOG SERVICE"),
        ((700, 150, 970, 210), "PAGE SERVERS"),
        ((440, 280, 750, 335), "AZURE STORAGE"),
    ]:
        d.rounded_rectangle(bounds, 10, fill=accent)
        d.text(((bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2),
               label, font=font(25, True), fill=PAPER, anchor="mm")

    # Arrows follow data: log and page reads point toward their consumers.
    arrow([(100, 65), (100, 150)], accent)
    d.text((116, 100), "Write log", font=font(19), fill=accent)
    d.line([(835, 150), (835, 80), (175, 80)], fill=read_color, width=4)
    d.line([(835, 80), (1100, 80)], fill=read_color, width=4)
    for x in (175, 650, 1100):
        arrow([(x, 80), (x, 65)], read_color)

    d.line([(240, 150), (240, 125), (1000, 125)], fill=log_color, width=4)
    # White gaps distinguish crossings from shared read-lane junctions.
    d.line([(835, 118), (835, 132)], fill=pale, width=10)
    d.line([(835, 118), (835, 132)], fill=read_color, width=4)
    for x in (550, 1000):
        d.line([(x, 73), (x, 87)], fill=pale, width=10)
        arrow([(x, 125), (x, 65)], log_color)
    arrow([(310, 180), (700, 180)], log_color)
    d.text((410, 149), "Read log", font=font(20), fill=log_color)
    arrow([(175, 210), (175, 305), (440, 305)], accent)
    arrow([(835, 210), (835, 305), (750, 305)], accent)
    for x, label, color in [
        (190, "Brown: writes", accent),
        (595, "Teal: log reads", log_color),
        (1000, "Blue: page reads", read_color),
    ]:
        d.text((x, 346), label, font=font(19, True), fill=color, anchor="mm")
    return im


def chapter_art(im, number, accent, scale=1):
    d = ScaledDraw(im, scale)
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

    def sql_icon(bounds):
        side = round(min(bounds[2] - bounds[0], bounds[3] - bounds[1]) * scale)
        icon = azure_sql_database_icon(side)
        position = (round((bounds[0] + bounds[2]) * scale / 2 - side / 2),
                    round((bounds[1] + bounds[3]) * scale / 2 - side / 2))
        im.paste(icon, position, icon)

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
        sql_icon((535, 360, 660, 478))
        centered(598, 484, "Azure SQL Hyperscale", 15, accent)
        arrow([(480, 424), (523, 424)])
    elif number == 3:
        im.paste(architecture_art(accent, scale).resize((610 * scale, 180 * scale),
                 Image.Resampling.LANCZOS), (80 * scale, 342 * scale))
    elif number == 4:
        with Image.open(ROOT / "figures" / "ch04-first-app" /
                        "ch04-fig-01-the-digital-chart-application.png") as screenshot:
            # Focus on the Unit board rather than spending thumbnail space on navigation.
            left = round(screenshot.width * 0.17)
            top = round(screenshot.height * 0.07)
            right = round(screenshot.width * 0.99)
            bottom = top + round((right - left) * 154 / 390)
            preview = screenshot.crop((left, top, right, bottom))
            preview.thumbnail((390 * scale, 154 * scale), Image.Resampling.LANCZOS)
            im.paste(preview, (92 * scale, 350 * scale))
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
        d.rounded_rectangle((92, 349, 366, 497), 8, outline=accent, width=2)
        centered(229, 355, "WARD GENERAL APP", 17, accent)
        box((106, 386, 351, 421), "HANDOFF AGENT", 17)
        box((405, 350, 515, 385), "LLM", 19)
        arrow([(351, 398), (383, 398), (383, 362), (405, 362)])
        arrow([(405, 375), (394, 375), (394, 411), (351, 411)])
        centered(229, 443, "LLM-led orchestration", 16, accent)
        centered(229, 473, "SQL MCP tool execution", 15, MUTED, False)
        box((405, 410, 515, 450), "SQL MCP", 17)
        box((557, 410, 677, 450), "HYPERSCALE", 14)
        arrow([(366, 431), (405, 431)])
        arrow([(405, 443), (366, 443)])
        arrow([(515, 424), (557, 424)])
        arrow([(557, 438), (515, 438)])
        arrow([(366, 486), (394, 486)])
        box((394, 477, 535, 510), "HUMAN APPROVAL", 12)
        arrow([(535, 493), (557, 493)])
        box((557, 477, 677, 510), "SAVE HANDOFF", 12)
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
        centered(588, 479, "Recover from a mistake quickly", 14, MUTED, False)
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
        for bounds, label in [((90, 352, 300, 394), "AZURE"),
                              ((470, 352, 680, 394), "MICROSOFT FOUNDRY"),
                              ((90, 405, 300, 447), "MIGRATE"),
                              ((470, 405, 680, 447), "AZURE APP SERVICE"),
                              ((90, 458, 300, 500), "CHANGE EVENT STREAMING"),
                              ((470, 458, 680, 500), "FABRIC MIRRORING")]:
            mid = ((bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2)
            d.line((center, mid), fill=accent, width=3)
            box(bounds, label, 14)
        d.rectangle((302, 450, 468, 478), fill=pale)
        sql_icon((335, 350, 435, 450))
        centered(385, 456, "AZURE SQL HYPERSCALE", 13, accent)


def chapter_illustration(number, accent, target_width):
    if number == 3:
        return architecture_art(accent, max(1, math.ceil(target_width / 1200)))
    scale = max(1, math.ceil(target_width / 610))
    artwork = Image.new("RGB", (S * scale, S * scale), PAPER)
    chapter_art(artwork, number, accent, scale)
    return artwork.crop(tuple(value * scale for value in (80, 342, 690, 522)))


def chapter_page(number, scale=1):
    im = background(scale)
    d = ScaledDraw(im, scale)
    accent = ACCENTS[number - 1]
    if args.v2:
        margin = 85 if args.landscape else 44
        available = W - margin * 2
        text(d, (margin, 92), f"CHAPTER {number:02d}", 22, accent, True)
        end = wrapped(d, (margin, 133), titles[number],
                      36 if args.landscape else 30, available,
                      bold=True, serif=True)
        assert end <= 250, (number, end)
        hero, _, _, takeaway = chapters[number - 1]
        end = wrapped(d, (margin, 225 if args.landscape else 253), hero,
                      27, available, accent, serif=True)
        assert end <= 323, (number, end)
        artwork = chapter_illustration(number, accent, available * scale)
        height = round(available * artwork.height / artwork.width)
        top = 280 if args.landscape else 345
        im.paste(artwork.resize((round(available * scale), round(height * scale)),
                 Image.Resampling.LANCZOS), (round(margin * scale), round(top * scale)))
        end = wrapped(d, (margin, top + height + 23), takeaway,
                      24, available, serif=True)
        assert end <= 696, (number, end)
        d.line((margin, 705, W - margin, 705), fill=(217, 222, 224))
        text(d, (W - margin - 90, 709), f"{number:02d} / 11", 16, accent)
        im.info["chapter_number"] = number
        return im
    if args.landscape:
        text(d, (85, 93), f"CHAPTER {number:02d}", 22, accent, True)
        end = wrapped(d, (85, 138), titles[number], 40, W - 170, bold=True, serif=True)
        assert end <= 250, (number, end)
        hero, labels, details, takeaway = chapters[number - 1]
        text(d, (85, 265), hero, 30, accent, serif=True)
        artwork = Image.new("RGB", (S, S), PAPER)
        chapter_art(artwork, number, accent)
        im.paste(artwork.crop((80, 342, 690, 522)).resize((780, 230),
                 Image.Resampling.LANCZOS), (85, 345))
        end = wrapped(d, (925, 345), takeaway, 28, 350, serif=True)
        assert end < 650, (number, end)
        d.line((85, 665, W - 85, 665), fill=(217, 222, 224), width=1)
        text(d, (85, 680), "AZURE SQL HYPERSCALE UNVEILED", 16, MUTED, serif=True)
        text(d, (W - 173, 680), f"{number:02d} / 11", 18, accent)
        return im
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
    im.info.pop("chapter_number", None)
    page_width, page_height = old.size
    if args.v2 and args.landscape and old.size == (W, S):
        im.info["page_turn"] = (old, new, progress)
    unit = page_height / S if page_width >= W else 1
    # A slanted, bowed fold exposes the next page; the translucent reverse
    # retains a hint of mirrored ink instead of becoming an opaque wipe.
    bend = math.sin(math.pi * progress)
    edge = page_width * (0.5 + 0.5 * math.cos(math.pi * progress))
    reverse = ImageOps.mirror(old)
    reverse = Image.blend(reverse, Image.new("RGB", old.size, PAPER), 0.92)
    for y in range(page_height):
        fraction = y / page_height
        bow = math.sin(math.pi * fraction)
        left = round(max(0, min(page_width, edge + bend * unit * (46 * (1 - 2 * fraction) - 28 * bow))))
        width = max(1, round(bend * (110 + 44 * bow) * page_width / page_height * unit))
        right = min(page_width, left + width)
        im.paste(old.crop((0, y, left, y + 1)), (0, y))
        if right <= left:
            continue
        # The shadow falls on the exposed page, following the paper's curve.
        shadow_end = min(page_width, right + round(25 * bend * unit))
        if shadow_end > right:
            shadow = im.crop((right, y, shadow_end, y + 1))
            shade = Image.new("RGB", shadow.size)
            sd = ImageDraw.Draw(shade)
            for x in range(shadow.width):
                value = round(160 + 95 * x / shadow.width)
                sd.point((x, 0), fill=(value, value, value))
            im.paste(ImageChops.multiply(shadow, shade), (right, y))
        strip = reverse.crop((max(0, left - round(150 * unit)), y, max(1, left), y + 1))
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
    d.rectangle((80, 108, 147, 113), fill=TEAL)
    text(d, (164, 96), "THE STORY CONTINUES", 21, TEAL, True)
    wrapped(d, (80, 143), "Build once. Evolve with confidence.", 36, 590,
            bold=True, serif=True)
    end = wrapped(d, (80, 254), SUMMARY_SUBTITLE, 23, 602, TEAL, serif=True)
    assert end <= 330, end
    text(d, (80, 337), "FROM CHAPTER 11 / QUOTE EXCERPT", 16, MUTED, True)
    quote = ARUN_QUOTE
    if args.landscape:
        im = background()
        d = ImageDraw.Draw(im)
        text(d, (90, 100), "THE STORY CONTINUES", 22, TEAL, True)
        text(d, (90, 158), "Build once. Evolve with confidence.", 44, INK, True, serif=True)
        text(d, (90, 237), SUMMARY_SUBTITLE, 29, TEAL, serif=True)
        text(d, (110, 310), "FROM CHAPTER 11 / QUOTE EXCERPT", 17, MUTED, True)
        end = wrapped(d, (110, 355), quote, 31, 1130, serif=True)
        assert end <= 610, end
        d.line((88, 360, 88, end - 5), fill=TEAL, width=3)
        text(d, (110, 631), "Arun Ulag", 26, INK, True, serif=True)
        text(d, (110, 671), "Vice President of Azure", 20, MUTED)
        return im
    end = wrapped(d, (96, 371), quote, 23, 574, serif=True)
    assert end <= 588, end
    d.line((80, 376, 80, end - 6), fill=TEAL, width=3)
    text(d, (96, 594), "Arun Ulag", 22, INK, True, serif=True)
    text(d, (96, 625), "Vice President of Azure", 17, MUTED)
    d.line((80, 657, 690, 657), fill=(200, 204, 199), width=1)
    text(d, (80, 668), "YOUR DATABASE NOW AND FOR THE FUTURE", 15, TEAL, True)
    return im


def book_sheet(number=None, closing=False):
    """Typeset one portrait sheet at the front cover's proportions."""
    page = Image.new("RGB", (540, 780), PAPER)
    d = ImageDraw.Draw(page)
    text(d, (40, 28), "AZURE SQL HYPERSCALE UNVEILED", 14, MUTED, serif=True)
    d.line((40, 58, 500, 58), fill=(218, 220, 218))
    if number is not None:
        accent = ACCENTS[number - 1]
        text(d, (40, 83), f"CHAPTER {number:02d}", 18, accent, True)
        end = wrapped(d, (40, 125), titles[number], 27, 460, bold=True, serif=True)
        assert end <= 265, (number, end)
        hero, _, _, takeaway = chapters[number - 1]
        end = wrapped(d, (40, 281), hero, 23, 460, accent, serif=True)
        assert end <= 345, (number, end)
        artwork = Image.new("RGB", (768, 768), PAPER)
        chapter_art(artwork, number, accent)
        page.paste(artwork.crop((80, 342, 690, 522)).resize((460, 136),
                   Image.Resampling.LANCZOS), (40, 365))
        wrapped(d, (40, 537), takeaway, 23, 460, serif=True)
        text(d, (439, 732), f"{number:02d} / 11", 16, accent)
    elif closing:
        wrapped(d, (40, 105), "Your next chapter starts here.", 37, 455,
                TEAL, True, serif=True)
        wrapped(d, (40, 264), "Powered by SQL Server. Cloud-native scale. AI built in.",
                28, 450, serif=True)
        text(d, (40, 444), "BOOK", 17, TEAL, True)
        text(d, (40, 480), "aka.ms/sqlhyperscaleunveiled", 25, INK, True)
        text(d, (40, 550), "CODE", 17, TEAL, True)
        text(d, (40, 586), "aka.ms/sqlhyperscalebook", 25, INK, True)
        text(d, (40, 632), "github.com/rgward/sqlhyperscalebook", 17, MUTED)
    else:
        wrapped(d, (40, 94), "Build once. Evolve with confidence.", 33, 460,
                bold=True, serif=True)
        end = wrapped(d, (40, 233), SUMMARY_SUBTITLE, 23, 460, TEAL, serif=True)
        assert end <= 342, end
        text(d, (40, 352), "CHAPTER 11 / QUOTE EXCERPT", 15, MUTED, True)
        quote = ARUN_QUOTE
        end = wrapped(d, (40, 389), quote, 22, 460, serif=True)
        assert end <= 660, end
        text(d, (40, 675), "Arun Ulag", 23, INK, True, serif=True)
        text(d, (40, 711), "Vice President of Azure", 17, MUTED)
    if number is not None:
        d.line((40, 714, 500, 714), fill=(218, 220, 218))
        text(d, (40, 735), "Bob Ward", 15, MUTED, serif=True)
    return page


def opening_sheet():
    page = book_sheet(closing=True)
    d = ImageDraw.Draw(page)
    d.rectangle((0, 80, 540, 425), fill=PAPER)
    text(d, (40, 96), "HYPERSCALE:", 30, TEAL, True, serif=True)
    wrapped(d, (40, 154), "The cloud-native database for today and your future.",
            32, 460, bold=True, serif=True)
    text(d, (40, 320), "Powered by SQL Server.", 25, TEAL, serif=True)
    text(d, (40, 365), "Cloud-native scale. AI built in.", 23, INK, serif=True)
    text(d, (40, 414), "Book examples: AI-assisted creation and learning.", 16, MUTED)
    return page


def mount_book(sheet, turned):
    stage = Image.new("RGB", (W, S), (0, 0, 0) if args.v2 else (240, 238, 233))
    d = ImageDraw.Draw(stage)
    left = (W - 470) // 2 + 12
    top = 40
    # Unread sheets sit on the right; a smaller turned stack collects at the spine.
    stack = 2 + min(turned, 14)
    unread = max(3, 28 - min(turned, 14) * 2)
    if not args.v2:
        d.rounded_rectangle((left - stack - 13, top - 6, left + 476 + unread, top + 691),
                            5, fill=(197, 191, 181))
        d.rectangle((left - stack - 11, top - 4, left + 474 + unread, top + 686), fill=(65, 48, 36))
    for edge in range(stack, 0, -2):
        x = left - edge
        d.rectangle((x, top + edge // 3, left + 471, top + 682),
                    fill=(254, 252, 246), outline=(202, 198, 188))
    d.rectangle((left - stack - 7, top, left - stack - 3, top + 680), fill=(102, 77, 53))
    for edge in range(unread, 0, -2):
        d.rectangle((left, top + edge // 3, left + 470 + edge, top + 680 + edge // 3),
                    fill=(254, 252, 246), outline=(193, 188, 177))
    stage.paste(sheet.resize((470, 680), Image.Resampling.LANCZOS), (left, top))
    for x in range(6):
        shade = 215 + x * 7
        d.line((left + x, top, left + x, top + 679), fill=(shade, shade, shade - 2))
    return stage


class OpenBook:
    def __init__(self, size, detail=1):
        self.size = size
        self.detail = detail

    @lru_cache(maxsize=1)
    def front_cover(self):
        return cover.resize((540 * self.detail, 780 * self.detail),
                            Image.Resampling.LANCZOS)

    @lru_cache(maxsize=4)
    def spread(self, kind):
        scale = self.detail
        page = Image.new("RGB", (1080 * scale, 780 * scale), PAPER)
        d = ScaledDraw(page, scale)
        if isinstance(kind, int):
            accent = ACCENTS[kind - 1]
            text(d, (40, 35), f"CHAPTER {kind:02d}", 20, accent, True)
            end = wrapped(d, (40, 95), titles[kind], 30, 455,
                          INK, True, serif=True)
            assert end <= 290, (kind, end)
            hero, _, _, takeaway = chapters[kind - 1]
            end = wrapped(d, (585, 95), hero, 27, 450, accent, serif=True)
            end = wrapped(d, (585, end + 25), takeaway, 23, 450, serif=True)
            assert end <= 300, (kind, end)
            artwork = chapter_illustration(kind, accent, 1000 * scale)
            height = round(1000 * artwork.height / artwork.width)
            page.paste(artwork.resize((1000 * scale, height * scale),
                       Image.Resampling.LANCZOS), (40 * scale, 320 * scale))
            text(d, (40, 726), "AZURE SQL HYPERSCALE UNVEILED", 15, TEAL, serif=True)
            text(d, (960, 726), f"{kind:02d} / 11", 17, accent)
        elif kind == "summary":
            text(d, (40, 45), "THE STORY CONTINUES", 20, TEAL, True)
            end = wrapped(d, (40, 110), "Build once. Evolve with confidence.",
                          34, 450, INK, True, serif=True)
            assert end <= 250, end
            end = wrapped(d, (40, 280), SUMMARY_SUBTITLE, 27, 450, TEAL, serif=True)
            assert end <= 490, end
            text(d, (585, 50), "CHAPTER 11 / QUOTE EXCERPT", 16, MUTED, True)
            end = wrapped(d, (585, 110), ARUN_QUOTE, 23, 450, serif=True)
            assert end <= 630, end
            text(d, (585, 670), "Arun Ulag", 25, INK, True, serif=True)
            text(d, (585, 714), "Vice President of Azure", 19, MUTED)
        else:
            assert kind in ("intro", "closing"), kind
            text(d, (40, 30), "AZURE SQL HYPERSCALE UNVEILED", 15, MUTED, serif=True)
            if kind == "intro":
                text(d, (40, 85), "DEDICATION", 18, TEAL, True)
                end = wrapped(d, (40, 124), BOOK_DEDICATION, 23, 450, serif=True)
                assert end <= 330, end
                text(d, (40, 350), "TECHNICAL REVIEWER", 16, MUTED, True)
                text(d, (40, 384), "Kendal Van Dyke", 26, INK, True, serif=True)
                text(d, (40, 458), "QUOTE CONTRIBUTORS", 16, MUTED, True)
                for index, name in enumerate(QUOTE_CONTRIBUTORS):
                    end = wrapped(d, (40, 495 + index * 29), name, 21, 450, serif=True)
                    assert end <= 730, (name, end)
            else:
                page.paste(self.front_cover().resize((330 * scale, 477 * scale),
                           Image.Resampling.LANCZOS), (100 * scale, 110 * scale))
            text(d, (585, 70), "HYPERSCALE:", 30, TEAL, True, serif=True)
            end = wrapped(d, (585, 125),
                          "The cloud-native database for today and your future.",
                          31, 450, INK, True, serif=True)
            assert end <= 310, end
            if kind == "closing":
                end = wrapped(d, (585, 335), "Your next chapter starts here.",
                              27, 450, TEAL, serif=True)
                assert end <= 420, end
            else:
                text(d, (585, 335), "Powered by SQL Server.", 25, TEAL, serif=True)
                text(d, (585, 380), "Cloud-native scale. AI built in.", 23, INK, serif=True)
            end = wrapped(d, (585, 435), "Architecture. Engine. Applications. AI. Azure.",
                          20, 450, serif=True)
            assert end <= 495, end
            end = wrapped(d, (585, 502), "Book examples: AI-assisted creation and guided learning.",
                          17, 450, MUTED)
            assert end <= 560, end
            text(d, (585, 575), "BOOK", 16, TEAL, True)
            text(d, (585, 606), BOOK_URL, 23, INK, True)
            text(d, (585, 658), "CODE", 16, TEAL, True)
            text(d, (585, 689), "aka.ms/sqlhyperscalebook", 23, INK, True)
            text(d, (585, 720), "github.com/rgward/sqlhyperscalebook", 14, MUTED)
        footer_width = d.textlength(BOOK_URL, font=font(16))
        for left in (0, 540):
            text(d, (left + (540 - footer_width) / 2, 750), BOOK_URL, 16, TEAL)
        return (page.crop((0, 0, 540 * scale, 780 * scale)),
                page.crop((540 * scale, 0, 1080 * scale, 780 * scale)))

    def base(self, left, right):
        scale = self.detail
        world = Image.new("RGB", (2400 * scale, 1400 * scale), (0, 0, 0))
        d = ScaledDraw(world, scale)
        for edge in (10, 7, 4):
            d.rectangle((1200, 310 + edge // 2, 1740 + edge, 1090 + edge // 2),
                        fill=(243, 241, 235), outline=(172, 169, 160), width=1)
            if left is not None:
                d.rectangle((660 - edge, 310 + edge // 2, 1200, 1090 + edge // 2),
                            fill=(243, 241, 235), outline=(172, 169, 160), width=1)
        if left is not None:
            world.paste(left, (660 * scale, 310 * scale))
        world.paste(right, (1200 * scale, 310 * scale))
        return world

    def gutter(self, world):
        scale = self.detail
        for offset in range(-5, 6):
            shade = 203 + abs(offset) * 10
            bounds = ((1200 + offset) * scale, 310 * scale,
                      (1201 + offset) * scale, 1090 * scale)
            band = world.crop(bounds)
            tint = Image.new("RGB", band.size, (shade, shade, shade))
            world.paste(ImageChops.multiply(band, tint), bounds[:2])

    def leaf(self, world, front, back, progress):
        scale = self.detail
        cosine, sine = math.cos(math.pi * progress), math.sin(math.pi * progress)
        if abs(cosine) < 0.002:
            ScaledDraw(world, scale).line((1200, 310, 1200, 1090),
                                         fill=(203, 201, 194), width=2)
            return
        texture = front if cosine > 0 else ImageOps.mirror(back)
        texture = ImageEnhance.Brightness(texture).enhance(0.79 + 0.21 * abs(cosine))
        for x in range(540 * scale):
            fraction = (x + 0.5) / scale
            perspective = 1 / (1 - fraction * sine / 4000)
            a = round((1200 + (x / scale) * cosine /
                       (1 - (x / scale) * sine / 4000)) * scale)
            b = round((1200 + ((x + 1) / scale) * cosine /
                       (1 - ((x + 1) / scale) * sine / 4000)) * scale)
            if a == b:
                continue
            height = round(780 * scale * perspective)
            strip = texture.crop((x, 0, x + 1, 780 * scale)).resize(
                (abs(b - a), height), Image.Resampling.BICUBIC)
            world.paste(strip, (min(a, b), round(700 * scale - height / 2)))
        perspective = 1 / (1 - 540 * sine / 4000)
        edge_x = 1200 + 540 * cosine * perspective
        ScaledDraw(world, scale).line(
            [(1200, 310), (edge_x, 700 - 390 * perspective),
             (edge_x, 700 + 390 * perspective), (1200, 1090)],
            fill=(185, 181, 170), width=1)

    def render(self, descriptor):
        mode, kind, previous, progress = descriptor
        left, right = self.spread(kind)
        if mode == "cover":
            world = self.base(left if progress == 1 else None, right)
            self.leaf(world, self.front_cover(), left, progress)
            if progress == 1:
                self.gutter(world)
            camera = progress
        elif mode == "turn":
            old_left, old_right = self.spread(previous)
            world = self.base(old_left, right)
            self.leaf(world, old_right, left, progress)
            self.gutter(world)
            camera = 1
        else:
            assert mode == "spread", mode
            world = self.base(left, right)
            self.gutter(world)
            camera = 1
        width, height = self.size
        view_height = (820 + (max(900, 1160 * height / width) - 820) * camera
                       + 45 * math.sin(math.pi * camera))
        view_width = view_height * width / height
        center_x = 1200 + 270 * (1 - camera)
        box = tuple(value * self.detail for value in (
            center_x - view_width / 2, 700 - view_height / 2,
            center_x + view_width / 2, 700 + view_height / 2))
        frame = world.resize(self.size, Image.Resampling.LANCZOS, box=box)
        return frame


def v2_sequence():
    renderer = OpenBook((W, S))
    result, timing = [], []
    gif_output = args.frames_dir is None

    def append(descriptor, delay):
        frame = (Image.new("RGB", (1, 1)) if args.frames_dir
                 else renderer.render(descriptor))
        frame.info["open_book"] = descriptor
        result.append(frame)
        timing.append(delay)

    delay = 40 if args.landscape else 60
    cover_steps = 60 if args.landscape else 40
    turn_steps = 15 if gif_output else (45 if args.landscape else 30)
    closing_steps = 20 if gif_output else cover_steps
    append(("cover", "intro", None, 0), 6000 if gif_output else 12000)
    for step in range(1, cover_steps + 1):
        t = step / cover_steps
        t = t * t * (3 - 2 * t)
        append(("cover", "intro", None, t), delay)
    append(("spread", "intro", None, 1), 6000 if gif_output else 14000)
    previous = "intro"
    for kind in list(range(1, 12)) + ["summary", "closing"]:
        for step in range(1, turn_steps + 1):
            t = step / turn_steps
            t = t * t * (3 - 2 * t)
            append(("turn", kind, previous, t), delay)
        if gif_output:
            hold = 7000 if kind == "summary" else 4000 if kind == "closing" else 2500
        else:
            hold = 14000 if kind == "summary" else 6000
        append(("spread", kind, None, 1), hold)
        previous = kind
    for step in range(1, closing_steps + 1):
        t = step / closing_steps
        t = t * t * (3 - 2 * t)
        append(("cover", "closing", None, 1 - t), delay)
    append(("cover", "closing", None, 0), 3000 if gif_output else 6000)
    pages = [renderer.render(("cover", "intro", None, 0))]
    pages += [renderer.render(("spread", kind, None, 1))
              for kind in ["intro"] + list(range(1, 12)) + ["summary", "closing"]]
    return result, timing, pages


if args.v2:
    frames, delays, pages = v2_sequence()
else:
    sheets = ([cover.resize((540, 780), Image.Resampling.LANCZOS), opening_sheet()]
              + [book_sheet(i) for i in range(1, 12)]
              + [book_sheet(), book_sheet(closing=True)])
    pages = [mount_book(sheet, i) for i, sheet in enumerate(sheets)]
    frames = [pages[0]]
    delays = [12000]
    for index in range(1, len(pages)):
        for step in range(1, 13):
            frames.append(mount_book(turn(sheets[index - 1], sheets[index], step / 13), index))
            delays.append(80)
        frames.append(pages[index])
        delays.append(14000 if index == len(pages) - 2 else 6000)
if args.preview_dir:
    args.preview_dir.mkdir(parents=True, exist_ok=True)
    thumb_width = 512 if args.landscape else 384
    thumb_height = round(S * thumb_width / W)
    sheet = Image.new("RGB", (thumb_width * 4, thumb_height * 4), PAPER)
    for i, page in enumerate(pages):
        sheet.paste(page.resize((thumb_width, thumb_height)),
                    ((i % 4) * thumb_width, (i // 4) * thumb_height))
    suffix = "landscape" if args.landscape else "square"
    sheet.save(args.preview_dir / f"chapter-storyboard-{suffix}.png")
    preview = frames[6]
    if "open_book" in preview.info:
        preview = OpenBook((W, S)).render(preview.info["open_book"])
    preview.save(args.preview_dir / f"page-turn-{suffix}.png")

if args.frames_dir:
    args.frames_dir.mkdir(parents=True, exist_ok=True)
    manifest = ["ffconcat version 1.0"]
    native_book = (OpenBook((3840, 2160), detail=3) if args.landscape
                   else OpenBook((W, S))) if args.v2 else None
    for i, (frame, delay) in enumerate(zip(frames, delays)):
        name = f"frame-{i:03d}.png"
        if args.v2:
            frame = native_book.render(frame.info["open_book"])
        frame.save(args.frames_dir / name)
        manifest.extend([f"file '{name}'", f"duration {delay / 1000:.3f}"])
    manifest.append(f"file 'frame-{len(frames) - 1:03d}.png'")
    (args.frames_dir / "frames.ffconcat").write_text("\n".join(manifest) + "\n", encoding="ascii")
    (args.frames_dir / "duration.txt").write_text(f"{sum(delays) / 1000:.3f}", encoding="ascii")
    size = "3840 x 2160" if args.v2 and args.landscape else f"{W} x {S}"
    print(f"Exported {len(frames)} {size} frames; duration {sum(delays) / 1000:.2f}s.")
    sys.exit(0)

palette_sheet = Image.new("RGB", (GIF_SIZE * len(pages), GIF_SIZE))
for i, page in enumerate(pages):
    palette_sheet.paste(page.resize((GIF_SIZE, GIF_SIZE), Image.Resampling.LANCZOS),
                        (i * GIF_SIZE, 0))
palette = palette_sheet.quantize(colors=GIF_COLORS, method=Image.Quantize.MEDIANCUT)
indexed = [frame.resize((GIF_SIZE, GIF_SIZE), Image.Resampling.LANCZOS).quantize(
    palette=palette, dither=Image.Dither.NONE) for frame in frames]
output = ROOT / "figures" / "book-chapters.gif"
indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=delays,
                loop=0, optimize=True, disposal=1)
with Image.open(output) as gif:
    total = 0
    for frame in range(gif.n_frames):
        gif.seek(frame)
        total += gif.info["duration"]
        gif.load()
    assert gif.size == (GIF_SIZE, GIF_SIZE) and gif.info["loop"] == 0
    assert total == sum(delays)
    if args.v2:
        assert total == 68800
        assert delays[0] == 6000 and delays[-1] == 3000
    else:
        assert delays[13::13] == [6000] * 12 + [14000, 6000]
        assert total == 117440
    assert output.stat().st_size < GIF_MAX_BYTES
    print(f"Verified: 11 chapters, {gif.n_frames} frames, {total / 1000:.2f}s, "
          f"{output.stat().st_size:,} bytes, infinite loop; all frames decoded.")
print(output)
