# Example: python .\msg_subfolders_to_pdf_with_attachments.py
# Variables: Set SOURCE to your MSG folder; see msg-input.example.txt for the folder layout.
#
from pathlib import Path
from datetime import datetime
from html.parser import HTMLParser
from email.utils import parsedate_to_datetime
import html
import re
import shutil
import subprocess
import traceback

import extract_msg

from PIL import Image as PILImage

from pypdf import PdfReader, PdfWriter

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
    Image,
)


# =========================
# CONFIG
# =========================

SOURCE = Path(r"C:\path\to\msg-files")

DEST = SOURCE / "PDF output"

LOG_NAME = "pdf-conversion-log.txt"

WORK = DEST / "_work"

CLEAN_WORK_AT_END = True

SUPPORTED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg"}
SUPPORTED_OFFICE_EXTENSIONS = {".docx"}
SUPPORTED_DIRECT_PDF_EXTENSIONS = {".pdf"}

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

        if tag == "br":
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


def unique_path(path):
    if not path.exists():
        return path

    parent = path.parent
    stem = path.stem
    suffix = path.suffix

    counter = 2

    while True:
        candidate = parent / f"{stem} ({counter}){suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def append_log(message):
    DEST.mkdir(parents=True, exist_ok=True)
    with (DEST / LOG_NAME).open("a", encoding="utf-8") as f:
        f.write(message.rstrip() + "\n")


def get_attachment_name(attachment, index):
    for attr in ("longFilename", "shortFilename", "name", "displayName"):
        try:
            value = getattr(attachment, attr, None)
            if value:
                return safe_filename(value)
        except Exception:
            pass

    try:
        value = attachment.getFilename()
        if value:
            return safe_filename(value)
    except Exception:
        pass

    return f"attachment_{index}"


def get_msg_body_text(msg):
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
    if not value:
        return "No date", datetime.max

    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S"), value.replace(tzinfo=None)

    text = str(value).strip()

    try:
        parsed = parsedate_to_datetime(text)
        if parsed:
            return parsed.strftime("%Y-%m-%d %H:%M:%S"), parsed.replace(tzinfo=None)
    except Exception:
        pass

    return text, datetime.max


def find_soffice():
    candidates = [
        shutil.which("soffice"),
        r"C:\Program Files\LibreOffice\program\soffice.exe",
        r"C:\Program Files (x86)\LibreOffice\program\soffice.exe",
    ]

    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(candidate)

    return None


def register_fonts():
    regular = Path(r"C:\Windows\Fonts\arial.ttf")
    bold = Path(r"C:\Windows\Fonts\arialbd.ttf")

    if regular.exists():
        pdfmetrics.registerFont(TTFont("Arial", str(regular)))

        if bold.exists():
            pdfmetrics.registerFont(TTFont("Arial-Bold", str(bold)))
            return "Arial", "Arial-Bold"

        return "Arial", "Arial"

    return "Helvetica", "Helvetica-Bold"


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
        name="AttachmentTitle",
        parent=styles["Heading1"],
        fontName=font_bold,
        fontSize=16,
        leading=20,
        spaceBefore=4,
        spaceAfter=10,
        textColor=colors.HexColor("#222222"),
    ))

    styles.add(ParagraphStyle(
        name="Meta",
        parent=styles["Normal"],
        fontName=font_regular,
        fontSize=9,
        leading=12,
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


def make_paragraph(text, style):
    text = str(text or "")
    text = html.escape(text)
    text = text.replace("\n", "<br/>")
    return Paragraph(text, style)


def page_footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#666666"))
    canvas.drawRightString(A4[0] - 18 * mm, 10 * mm, f"Page {doc.page}")
    canvas.restoreState()


# =========================
# PDF UTILS
# =========================

def add_pdf_to_writer(writer, pdf_path):
    reader = PdfReader(str(pdf_path))

    for page in reader.pages:
        writer.add_page(page)


def make_simple_pdf(output_pdf, title, lines):
    styles = build_styles()

    doc = SimpleDocTemplate(
        str(output_pdf),
        pagesize=A4,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title=title,
    )

    story = [
        Paragraph(html.escape(title), styles["AttachmentTitle"]),
        Spacer(1, 8),
    ]

    for line in lines:
        story.append(make_paragraph(line, styles["Body"]))

    doc.build(story, onFirstPage=page_footer, onLaterPages=page_footer)


def make_image_pdf(image_path, output_pdf, title=None, parent_subject=None):
    output_pdf.parent.mkdir(parents=True, exist_ok=True)

    styles = build_styles()

    doc = SimpleDocTemplate(
        str(output_pdf),
        pagesize=A4,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title=title or image_path.name,
    )

    story = []

    page_width, page_height = A4
    max_width = page_width - 36 * mm
    max_height = page_height - 36 * mm

    if title:
        story.append(Paragraph(html.escape(title), styles["AttachmentTitle"]))
        story.append(Spacer(1, 4))
        max_height -= 18 * mm

    if parent_subject:
        story.append(make_paragraph(f"Parent email: {parent_subject}", styles["SmallMuted"]))
        story.append(Spacer(1, 8))
        max_height -= 12 * mm

    with PILImage.open(image_path) as img:
        width_px, height_px = img.size

    ratio = min(max_width / width_px, max_height / height_px)

    # Do not upscale small images aggressively.
    ratio = min(ratio, 1.0)

    display_width = width_px * ratio
    display_height = height_px * ratio

    story.append(Image(str(image_path), width=display_width, height=display_height))

    doc.build(story, onFirstPage=page_footer, onLaterPages=page_footer)


def convert_docx_to_pdf(docx_path, output_dir):
    soffice = find_soffice()

    if not soffice:
        raise RuntimeError("LibreOffice soffice.exe not found. Install LibreOffice or add soffice.exe to PATH.")

    output_dir.mkdir(parents=True, exist_ok=True)

    command = [
        soffice,
        "--headless",
        "--convert-to",
        "pdf",
        "--outdir",
        str(output_dir),
        str(docx_path),
    ]

    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )

    expected_pdf = output_dir / f"{docx_path.stem}.pdf"

    if result.returncode != 0 or not expected_pdf.exists():
        raise RuntimeError(
            "LibreOffice failed to convert DOCX.\n"
            f"Command: {' '.join(command)}\n"
            f"stdout: {result.stdout}\n"
            f"stderr: {result.stderr}"
        )

    return expected_pdf


def make_attachment_intro_pdf(output_pdf, parent_subject, attachment_name, attachment_number, attachment_count):
    make_simple_pdf(
        output_pdf,
        f"Attachment {attachment_number} of {attachment_count}",
        [
            f"Parent email: {parent_subject}",
            f"Attachment: {attachment_name}",
        ],
    )


# =========================
# MSG READ / EXTRACT
# =========================

def read_msg_summary_and_extract_attachments(msg_path, attachment_output_dir):
    msg = None

    try:
        msg = extract_msg.Message(str(msg_path))

        subject = getattr(msg, "subject", None) or "No subject"
        sender = getattr(msg, "sender", None) or ""
        to = getattr(msg, "to", None) or ""
        cc = getattr(msg, "cc", None) or ""
        date_raw = getattr(msg, "date", None)

        display_date, sort_key = parse_msg_date(date_raw)

        body_text = get_msg_body_text(msg)

        attachments = []

        raw_attachments = getattr(msg, "attachments", []) or []

        if raw_attachments:
            attachment_output_dir.mkdir(parents=True, exist_ok=True)

        for index, attachment in enumerate(raw_attachments, start=1):
            attachment_name = get_attachment_name(attachment, index)
            target_path = unique_path(attachment_output_dir / attachment_name)

            try:
                attachment.save(
                    customPath=str(attachment_output_dir),
                    customFilename=target_path.name,
                )

                attachments.append({
                    "name": target_path.name,
                    "path": target_path,
                    "status": "saved",
                    "error": "",
                })

                append_log(f"OK ATTACHMENT SAVE: {target_path}")

            except Exception as exc:
                attachments.append({
                    "name": attachment_name,
                    "path": None,
                    "status": "failed",
                    "error": str(exc),
                })

                append_log(f"FAILED ATTACHMENT SAVE: {msg_path} attachment {index} {attachment_name}")
                append_log(traceback.format_exc())
                append_log("")

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


# =========================
# EMAIL PDF
# =========================

def build_single_email_pdf(email_item, output_pdf):
    styles = build_styles()

    doc = SimpleDocTemplate(
        str(output_pdf),
        pagesize=A4,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title=email_item["subject"],
        author="MSG PDF conversion script",
    )

    story = []

    header_block = [
        Paragraph(
            f"{email_item['number']:03}. {html.escape(email_item['subject'])}",
            styles["EmailTitle"],
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
        for index, attachment in enumerate(email_item["attachments"], start=1):
            status_note = ""

            if attachment["status"] != "saved":
                status_note = " [failed to extract]"

            story.append(make_paragraph(f"- {index}. {attachment['name']}{status_note}", styles["Body"]))
    else:
        story.append(make_paragraph("None", styles["SmallMuted"]))

    story.append(Paragraph("Message", styles["SectionHeading"]))

    body_text = email_item["body_text"].strip()

    if not body_text:
        story.append(make_paragraph("[No readable message body found]", styles["SmallMuted"]))
    else:
        paragraphs = re.split(r"\n\s*\n", body_text)

        for para in paragraphs:
            para = para.strip()

            if para:
                story.append(make_paragraph(para, styles["Body"]))

    doc.build(story, onFirstPage=page_footer, onLaterPages=page_footer)


# =========================
# ATTACHMENT RENDERING
# =========================

def render_attachment_to_pdf(attachment, parent_subject, attachment_number, attachment_count, work_folder):
    work_folder.mkdir(parents=True, exist_ok=True)

    attachment_name = attachment["name"]
    attachment_path = attachment["path"]

    safe_stem = safe_filename(Path(attachment_name).stem)
    rendered_pdf = work_folder / f"attachment_{attachment_number:03}_{safe_stem}.pdf"

    if attachment["status"] != "saved" or not attachment_path or not attachment_path.exists():
        fail_pdf = work_folder / f"attachment_{attachment_number:03}_{safe_stem}_failed.pdf"
        make_simple_pdf(
            fail_pdf,
            f"Attachment could not be extracted: {attachment_name}",
            [
                f"Parent email: {parent_subject}",
                f"Attachment: {attachment_name}",
                f"Error: {attachment.get('error') or 'Unknown error'}",
            ],
        )

        return [fail_pdf]

    extension = attachment_path.suffix.lower()

    try:
        if extension in SUPPORTED_DIRECT_PDF_EXTENSIONS:
            return [attachment_path]

        if extension in SUPPORTED_IMAGE_EXTENSIONS:
            make_image_pdf(
                image_path=attachment_path,
                output_pdf=rendered_pdf,
                title=f"Attachment {attachment_number} of {attachment_count}: {attachment_name}",
                parent_subject=parent_subject,
            )
            return [rendered_pdf]

        if extension in SUPPORTED_OFFICE_EXTENSIONS:
            converted_pdf = convert_docx_to_pdf(
                docx_path=attachment_path,
                output_dir=work_folder,
            )
            return [converted_pdf]

        unsupported_pdf = work_folder / f"attachment_{attachment_number:03}_{safe_stem}_unsupported.pdf"
        make_simple_pdf(
            unsupported_pdf,
            f"Unsupported attachment type: {attachment_name}",
            [
                f"Parent email: {parent_subject}",
                f"Attachment: {attachment_name}",
                f"File type: {extension or '[no extension]'}",
                "This attachment was extracted but not rendered into the bundle PDF.",
            ],
        )
        return [unsupported_pdf]

    except Exception as exc:
        failed_render_pdf = work_folder / f"attachment_{attachment_number:03}_{safe_stem}_render_failed.pdf"

        make_simple_pdf(
            failed_render_pdf,
            f"Attachment render failed: {attachment_name}",
            [
                f"Parent email: {parent_subject}",
                f"Attachment: {attachment_name}",
                f"Error: {exc}",
            ],
        )

        append_log(f"FAILED ATTACHMENT RENDER: {attachment_path}")
        append_log(traceback.format_exc())
        append_log("")

        return [failed_render_pdf]


# =========================
# FOLDER PDF BUILD
# =========================

def build_folder_pdf(folder_path, msg_files, output_pdf):
    folder_work = WORK / safe_filename(folder_path.name)

    if folder_work.exists():
        shutil.rmtree(folder_work)

    folder_work.mkdir(parents=True, exist_ok=True)

    emails = []

    for msg_path in msg_files:
        try:
            attachment_output_dir = folder_work / "attachments" / safe_filename(msg_path.stem)
            email_item = read_msg_summary_and_extract_attachments(msg_path, attachment_output_dir)
            emails.append(email_item)
            append_log(f"OK READ: {msg_path}")
        except Exception:
            append_log(f"FAILED READ: {msg_path}")
            append_log(traceback.format_exc())
            append_log("")

    emails.sort(key=lambda item: (item["sort_key"], str(item["path"]).lower()))

    writer = PdfWriter()

    cover_pdf = folder_work / "000_cover.pdf"

    make_simple_pdf(
        cover_pdf,
        f"Email bundle: {folder_path.name}",
        [
            f"Source folder: {folder_path}",
            f"Email count: {len(emails)}",
            "Each email is followed by its rendered attachments where possible.",
            "Supported rendered attachment types: PDF, PNG, JPG, JPEG, DOCX.",
        ],
    )

    add_pdf_to_writer(writer, cover_pdf)

    for index, email_item in enumerate(emails, start=1):
        email_item["number"] = index

        email_pdf = folder_work / f"email_{index:03}.pdf"
        build_single_email_pdf(email_item, email_pdf)

        add_pdf_to_writer(writer, email_pdf)

        attachments = email_item["attachments"]

        for attachment_number, attachment in enumerate(attachments, start=1):
            rendered_parts = render_attachment_to_pdf(
                attachment=attachment,
                parent_subject=email_item["subject"],
                attachment_number=attachment_number,
                attachment_count=len(attachments),
                work_folder=folder_work / f"email_{index:03}_attachment_rendered",
            )

            for part_pdf in rendered_parts:
                try:
                    add_pdf_to_writer(writer, part_pdf)
                except Exception:
                    append_log(f"FAILED PDF APPEND: {part_pdf}")
                    append_log(traceback.format_exc())
                    append_log("")

                    append_fail_pdf = folder_work / f"email_{index:03}_attachment_{attachment_number:03}_append_failed.pdf"
                    make_simple_pdf(
                        append_fail_pdf,
                        "Attachment could not be added to final PDF",
                        [
                            f"Parent email: {email_item['subject']}",
                            f"Attachment: {attachment['name']}",
                            f"PDF path: {part_pdf}",
                        ],
                    )
                    add_pdf_to_writer(writer, append_fail_pdf)

    output_pdf.parent.mkdir(parents=True, exist_ok=True)

    with output_pdf.open("wb") as f:
        writer.write(f)


# =========================
# MAIN
# =========================

def main():
    DEST.mkdir(parents=True, exist_ok=True)

    log_path = DEST / LOG_NAME
    if log_path.exists():
        log_path.unlink()

    if WORK.exists():
        shutil.rmtree(WORK)

    WORK.mkdir(parents=True, exist_ok=True)

    append_log(f"Source: {SOURCE}")
    append_log(f"Destination: {DEST}")
    append_log(f"Work folder: {WORK}")
    append_log("")

    if not SOURCE.exists():
        raise FileNotFoundError(f"Source folder does not exist: {SOURCE}")

    subfolders = [
        item for item in SOURCE.iterdir()
        if item.is_dir()
        and item.name != DEST.name
        and item.name != WORK.name
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

    if CLEAN_WORK_AT_END and WORK.exists():
        try:
            shutil.rmtree(WORK)
        except Exception:
            append_log(f"FAILED TO CLEAN WORK FOLDER: {WORK}")
            append_log(traceback.format_exc())

    print("Done.")
    print(f"PDFs written to: {DEST}")
    print(f"Log written to: {DEST / LOG_NAME}")


if __name__ == "__main__":
    main()