# Example: python .\msg_subfolders_to_pdf.py
# Variables: Set SOURCE to your MSG folder; see msg-input.example.txt for the folder layout.
#
from pathlib import Path
from datetime import datetime
from html.parser import HTMLParser
from email.utils import parsedate_to_datetime
import html
import re
import traceback

import extract_msg

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    PageBreak,
    KeepTogether,
)


# =========================
# CONFIG
# =========================

SOURCE = Path(r"C:\path\to\msg-files")

# Output PDFs go here, one per subfolder:
DEST = SOURCE / "PDF output"

LOG_NAME = "pdf-conversion-log.txt"

# If True, each PDF is written inside its matching source subfolder instead.
WRITE_PDFS_INSIDE_SOURCE_SUBFOLDERS = False


# =========================
# HTML TO TEXT
# =========================

class HTMLToText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip = False

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()

        if tag in ("script", "style"):
            self.skip = True

        if tag in ("br",):
            self.parts.append("\n")

        if tag in ("p", "div", "tr", "table", "ul", "ol", "li", "h1", "h2", "h3"):
            self.parts.append("\n")

        if tag == "li":
            self.parts.append("- ")

    def handle_endtag(self, tag):
        tag = tag.lower()

        if tag in ("script", "style"):
            self.skip = False

        if tag in ("p", "div", "tr", "table", "ul", "ol", "li", "h1", "h2", "h3"):
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)

    def get_text(self):
        text = "".join(self.parts)
        text = html.unescape(text)
        text = re.sub(r"\r\n?", "\n", text)
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()


def html_to_text(value):
    if not value:
        return ""

    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")

    parser = HTMLToText()
    try:
        parser.feed(str(value))
        return parser.get_text()
    except Exception:
        return str(value)


# =========================
# HELPERS
# =========================

def safe_filename(value, max_len=120):
    value = str(value or "blank")
    value = value.replace("\u0000", "")
    value = re.sub(r'[<>:"/\\|?*\r\n\t]+', "_", value)
    value = re.sub(r"\s+", " ", value).strip()
    value = value.strip(" .")
    return (value[:max_len] or "blank").strip(" .")


def append_log(message):
    DEST.mkdir(parents=True, exist_ok=True)
    with (DEST / LOG_NAME).open("a", encoding="utf-8") as f:
        f.write(message.rstrip() + "\n")


def get_attachment_name(attachment, index):
    for attr in ("longFilename", "shortFilename", "name", "displayName"):
        try:
            value = getattr(attachment, attr, None)
            if value:
                return str(value)
        except Exception:
            pass

    try:
        value = attachment.getFilename()
        if value:
            return str(value)
    except Exception:
        pass

    return f"attachment_{index}"


def get_msg_body_text(msg):
    """
    Prefer HTML body if present, then fall back to plain text.
    """
    try:
        html_body = getattr(msg, "htmlBody", None)
        if html_body:
            return html_to_text(html_body)
    except Exception:
        pass

    try:
        body = getattr(msg, "body", None)
        if body:
            if isinstance(body, bytes):
                body = body.decode("utf-8", errors="replace")
            return str(body).strip()
    except Exception:
        pass

    return ""


def parse_msg_date(value):
    """
    Returns:
      display_date: string for humans
      sort_key: datetime for sorting
    """
    if not value:
        return "No date", datetime.max

    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S"), value

    text = str(value).strip()

    try:
        parsed = parsedate_to_datetime(text)
        if parsed:
            return parsed.strftime("%Y-%m-%d %H:%M:%S"), parsed.replace(tzinfo=None)
    except Exception:
        pass

    # Fallback: display the raw value and sort by text-ish max.
    return text, datetime.max


def register_fonts():
    """
    ReportLab's default Helvetica is limited. On Windows, Arial is usually present.
    This registers Arial if available.
    """
    candidates = [
        Path(r"C:\Windows\Fonts\arial.ttf"),
        Path(r"C:\Windows\Fonts\arialbd.ttf"),
    ]

    regular = candidates[0]
    bold = candidates[1]

    if regular.exists():
        pdfmetrics.registerFont(TTFont("Arial", str(regular)))

        if bold.exists():
            pdfmetrics.registerFont(TTFont("Arial-Bold", str(bold)))
            return "Arial", "Arial-Bold"

        return "Arial", "Arial"

    return "Helvetica", "Helvetica-Bold"


def make_paragraph(text, style):
    """
    Escape text safely for ReportLab Paragraph.
    """
    text = str(text or "")
    text = html.escape(text)
    text = text.replace("\n", "<br/>")
    return Paragraph(text, style)


def build_styles():
    font_regular, font_bold = register_fonts()

    styles = getSampleStyleSheet()

    styles.add(ParagraphStyle(
        name="ArchiveTitle",
        parent=styles["Title"],
        fontName=font_bold,
        fontSize=18,
        leading=22,
        spaceAfter=10,
        alignment=TA_LEFT,
    ))

    styles.add(ParagraphStyle(
        name="FolderSubTitle",
        parent=styles["Normal"],
        fontName=font_regular,
        fontSize=9,
        leading=12,
        textColor=colors.HexColor("#555555"),
        spaceAfter=12,
    ))

    styles.add(ParagraphStyle(
        name="EmailTitle",
        parent=styles["Heading1"],
        fontName=font_bold,
        fontSize=14,
        leading=17,
        spaceBefore=4,
        spaceAfter=8,
        textColor=colors.HexColor("#222222"),
    ))

    styles.add(ParagraphStyle(
        name="Meta",
        parent=styles["Normal"],
        fontName=font_regular,
        fontSize=9,
        leading=12,
        leftIndent=0,
        spaceAfter=2,
    ))

    styles.add(ParagraphStyle(
        name="SectionHeading",
        parent=styles["Heading2"],
        fontName=font_bold,
        fontSize=11,
        leading=14,
        spaceBefore=10,
        spaceAfter=5,
        textColor=colors.HexColor("#333333"),
    ))

    styles.add(ParagraphStyle(
        name="Body",
        parent=styles["Normal"],
        fontName=font_regular,
        fontSize=10,
        leading=13,
        spaceAfter=8,
    ))

    styles.add(ParagraphStyle(
        name="SmallMuted",
        parent=styles["Normal"],
        fontName=font_regular,
        fontSize=8,
        leading=10,
        textColor=colors.HexColor("#666666"),
    ))

    return styles


def page_footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#666666"))

    footer_text = f"Page {doc.page}"
    canvas.drawRightString(A4[0] - 18 * mm, 10 * mm, footer_text)

    canvas.restoreState()


# =========================
# PDF BUILDING
# =========================

def read_msg_summary(msg_path):
    msg = None

    try:
        msg = extract_msg.Message(str(msg_path))

        subject = getattr(msg, "subject", None) or "No subject"
        sender = getattr(msg, "sender", None) or ""
        to = getattr(msg, "to", None) or ""
        cc = getattr(msg, "cc", None) or ""
        date_raw = getattr(msg, "date", None)

        display_date, sort_key = parse_msg_date(date_raw)

        attachments = []
        for index, attachment in enumerate(getattr(msg, "attachments", []) or [], start=1):
            attachments.append(get_attachment_name(attachment, index))

        body_text = get_msg_body_text(msg)

        return {
            "path": msg_path,
            "subject": subject,
            "sender": sender,
            "to": to,
            "cc": cc,
            "display_date": display_date,
            "sort_key": sort_key,
            "attachments": attachments,
            "body_text": body_text,
        }

    finally:
        if msg is not None:
            try:
                msg.close()
            except Exception:
                pass


def build_folder_pdf(folder_path, msg_files, output_pdf):
    styles = build_styles()

    doc = SimpleDocTemplate(
        str(output_pdf),
        pagesize=A4,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title=folder_path.name,
        author="MSG PDF conversion script",
    )

    story = []

    story.append(Paragraph(f"Email bundle: {html.escape(folder_path.name)}", styles["ArchiveTitle"]))
    story.append(Paragraph(f"Source folder: {html.escape(str(folder_path))}", styles["FolderSubTitle"]))

    emails = []

    for msg_path in msg_files:
        try:
            emails.append(read_msg_summary(msg_path))
            append_log(f"OK READ: {msg_path}")
        except Exception:
            append_log(f"FAILED READ: {msg_path}")
            append_log(traceback.format_exc())
            append_log("")

    emails.sort(key=lambda item: (item["sort_key"], str(item["path"]).lower()))

    for index, email_item in enumerate(emails, start=1):
        if index > 1:
            story.append(PageBreak())

        header_block = [
            Paragraph(
                f"{index:03}. {html.escape(email_item['subject'])}",
                styles["EmailTitle"]
            ),
            make_paragraph(f"From: {email_item['sender']}", styles["Meta"]),
            make_paragraph(f"To: {email_item['to']}", styles["Meta"]),
            make_paragraph(f"Cc: {email_item['cc']}", styles["Meta"]),
            make_paragraph(f"Date: {email_item['display_date']}", styles["Meta"]),
            make_paragraph(f"Source file: {email_item['path'].name}", styles["SmallMuted"]),
            Spacer(1, 6),
        ]

        story.append(KeepTogether(header_block))

        story.append(Paragraph("Attachments", styles["SectionHeading"]))

        if email_item["attachments"]:
            for attachment_name in email_item["attachments"]:
                story.append(make_paragraph(f"- {attachment_name}", styles["Body"]))
        else:
            story.append(make_paragraph("None", styles["SmallMuted"]))

        story.append(Paragraph("Message", styles["SectionHeading"]))

        body_text = email_item["body_text"].strip()

        if not body_text:
            story.append(make_paragraph("[No readable message body found]", styles["SmallMuted"]))
        else:
            # Split into paragraphs so long emails flow properly.
            paragraphs = re.split(r"\n\s*\n", body_text)

            for para in paragraphs:
                para = para.strip()
                if para:
                    story.append(make_paragraph(para, styles["Body"]))

    if not emails:
        story.append(make_paragraph("No readable .msg files found in this folder.", styles["Body"]))

    doc.build(story, onFirstPage=page_footer, onLaterPages=page_footer)


# =========================
# MAIN
# =========================

def main():
    DEST.mkdir(parents=True, exist_ok=True)

    log_path = DEST / LOG_NAME
    if log_path.exists():
        log_path.unlink()

    append_log(f"Source: {SOURCE}")
    append_log(f"Destination: {DEST}")
    append_log("")

    if not SOURCE.exists():
        raise FileNotFoundError(f"Source folder does not exist: {SOURCE}")

    subfolders = [
        item for item in SOURCE.iterdir()
        if item.is_dir() and item.name != DEST.name
    ]

    if not subfolders:
        print("No subfolders found.")
        append_log("No subfolders found.")
        return

    for folder in sorted(subfolders, key=lambda p: p.name.lower()):
        msg_files = sorted(folder.glob("*.msg"))

        if not msg_files:
            append_log(f"SKIPPED, no .msg files: {folder}")
            continue

        if WRITE_PDFS_INSIDE_SOURCE_SUBFOLDERS:
            output_pdf = folder / f"{safe_filename(folder.name)}.pdf"
        else:
            output_pdf = DEST / f"{safe_filename(folder.name)}.pdf"

        try:
            print(f"Building: {output_pdf}")
            build_folder_pdf(folder, msg_files, output_pdf)
            append_log(f"OK PDF: {output_pdf}")
            append_log("")
        except Exception:
            append_log(f"FAILED PDF: {folder}")
            append_log(traceback.format_exc())
            append_log("")

    print("Done.")
    print(f"PDFs written to: {DEST}")
    print(f"Log written to: {DEST / LOG_NAME}")


if __name__ == "__main__":
    main()
