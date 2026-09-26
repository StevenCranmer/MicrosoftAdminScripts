# Example: python .\convert_msg_archive.py
# Variables: Set SOURCE and DEST to your MSG input and output folders; see msg-input.example.txt for the folder layout.
#
from pathlib import Path
from datetime import datetime
from urllib.parse import quote
import html
import re
import traceback

import extract_msg


# =========================
# CONFIG
# =========================

SOURCE = Path(r"C:\path\to\msg-files")
DEST = Path(r"C:\path\to\msg-files")

TOP_INDEX_NAME = "START HERE.html"
FOLDER_INDEX_NAME = "Folder index.html"
LOG_NAME = "conversion-log.txt"


# =========================
# HELPERS
# =========================

def safe_filename(value, max_len=120):
    """
    Make a string safe for Windows filenames.
    """
    value = str(value or "blank")
    value = value.replace("\u0000", "")
    value = re.sub(r'[<>:"/\\|?*\r\n\t]+', "_", value)
    value = re.sub(r"\s+", " ", value).strip()
    value = value.strip(" .")
    return (value[:max_len] or "blank").strip(" .")


def unique_path(path):
    """
    If a path already exists, append (2), (3), etc.
    """
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


def html_escape(value):
    return html.escape(str(value or ""))


def href_for(path):
    """
    Make a relative href safe for HTML links.
    Uses forward slashes because browsers handle them properly.
    """
    return quote(str(path).replace("\\", "/"))


def write_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def append_log(message):
    DEST.mkdir(parents=True, exist_ok=True)
    with (DEST / LOG_NAME).open("a", encoding="utf-8") as f:
        f.write(message.rstrip() + "\n")


def normalise_date(value):
    """
    Returns:
      display_date: human-readable date string
      sort_key: sortable string
      filename_date: safe date string for filenames
    """
    if not value:
        return "No date", "9999-99-99 99:99:99", "no-date"

    text = str(value).strip()

    # extract-msg often returns a datetime-like object or a string.
    if isinstance(value, datetime):
        return (
            value.strftime("%Y-%m-%d %H:%M:%S"),
            value.strftime("%Y-%m-%d %H:%M:%S"),
            value.strftime("%Y-%m-%d"),
        )

    # Try common useful prefix.
    filename_date = safe_filename(text[:10]) if len(text) >= 10 else "no-date"

    return text, text, filename_date


def get_attachment_name(attachment, index):
    """
    Pull the best available filename from extract-msg attachment objects.
    """
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


def get_message_body(msg):
    """
    Prefer HTML body. Fall back to plain text body.
    """
    body = None
    body_type = "plain"

    try:
        if msg.htmlBody:
            body = msg.htmlBody
            body_type = "html"
    except Exception:
        pass

    if body is None:
        try:
            body = msg.body or ""
            body_type = "plain"
        except Exception:
            body = ""
            body_type = "plain"

    if isinstance(body, bytes):
        body = body.decode("utf-8", errors="replace")

    if body_type == "html":
        return str(body)

    return f"<pre>{html_escape(body)}</pre>"


def render_email_page(email):
    attachments_html = ""

    if email["attachments"]:
        rows = []
        for att in email["attachments"]:
            rows.append(
                f"""
                <li>
                    <a href="{href_for(att['relative_path'])}">{html_escape(att['name'])}</a>
                </li>
                """
            )

        attachments_html = f"""
        <section class="attachments">
            <h2>Attachments</h2>
            <ul>
                {''.join(rows)}
            </ul>
        </section>
        """
    else:
        attachments_html = """
        <section class="attachments">
            <h2>Attachments</h2>
            <p class="muted">None</p>
        </section>
        """

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{html_escape(email["subject"])}</title>
<style>
body {{
    font-family: Arial, Helvetica, sans-serif;
    margin: 0;
    background: #f4f4f4;
    color: #222;
}}
.container {{
    max-width: 1000px;
    margin: 24px auto;
    background: white;
    border: 1px solid #d0d0d0;
    padding: 24px;
}}
h1 {{
    font-size: 22px;
    margin-top: 0;
}}
h2 {{
    font-size: 18px;
    margin-top: 28px;
    border-bottom: 1px solid #ddd;
    padding-bottom: 6px;
}}
.meta {{
    border: 1px solid #ddd;
    background: #fafafa;
    padding: 12px;
    margin-bottom: 20px;
}}
.meta-row {{
    margin: 6px 0;
}}
.label {{
    display: inline-block;
    min-width: 90px;
    font-weight: bold;
}}
.attachments {{
    border: 1px solid #ddd;
    background: #fbfbfb;
    padding: 12px;
    margin-bottom: 20px;
}}
.message {{
    margin-top: 20px;
}}
pre {{
    white-space: pre-wrap;
    font-family: Consolas, monospace;
    font-size: 14px;
}}
a {{
    color: #0645ad;
}}
.muted {{
    color: #666;
}}
.back {{
    margin-bottom: 16px;
}}
</style>
</head>
<body>
<div class="container">

<div class="back">
    <a href="{href_for(Path(FOLDER_INDEX_NAME))}">Back to folder index</a>
</div>

<h1>{html_escape(email["subject"])}</h1>

<section class="meta">
    <div class="meta-row"><span class="label">From:</span> {html_escape(email["sender"])}</div>
    <div class="meta-row"><span class="label">To:</span> {html_escape(email["to"])}</div>
    <div class="meta-row"><span class="label">Cc:</span> {html_escape(email["cc"])}</div>
    <div class="meta-row"><span class="label">Date:</span> {html_escape(email["display_date"])}</div>
    <div class="meta-row"><span class="label">Subject:</span> {html_escape(email["subject"])}</div>
    <div class="meta-row"><span class="label">Source:</span> {html_escape(email["source"])}</div>
</section>

{attachments_html}

<section class="message">
    <h2>Message</h2>
    {email["body_html"]}
</section>

</div>
</body>
</html>
"""


def render_folder_index(folder_name, emails):
    rows = []

    for email in emails:
        attachment_summary = "None"

        if email["attachments"]:
            attachment_summary = ", ".join(att["name"] for att in email["attachments"])

        rows.append(
            f"""
            <tr>
                <td>{email["number"]:03}</td>
                <td>{html_escape(email["display_date"])}</td>
                <td>{html_escape(email["sender"])}</td>
                <td><a href="{href_for(email["html_file"].name)}">{html_escape(email["subject"])}</a></td>
                <td>{html_escape(attachment_summary)}</td>
            </tr>
            """
        )

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{html_escape(folder_name)} - Email index</title>
<style>
body {{
    font-family: Arial, Helvetica, sans-serif;
    margin: 0;
    background: #f4f4f4;
    color: #222;
}}
.container {{
    max-width: 1200px;
    margin: 24px auto;
    background: white;
    border: 1px solid #d0d0d0;
    padding: 24px;
}}
h1 {{
    font-size: 24px;
    margin-top: 0;
}}
table {{
    border-collapse: collapse;
    width: 100%;
}}
th, td {{
    border: 1px solid #ddd;
    padding: 8px;
    vertical-align: top;
}}
th {{
    background: #eee;
    text-align: left;
}}
tr:nth-child(even) {{
    background: #fafafa;
}}
a {{
    color: #0645ad;
}}
.note {{
    background: #fbfbfb;
    border: 1px solid #ddd;
    padding: 12px;
    margin-bottom: 20px;
}}
</style>
</head>
<body>
<div class="container">

<p><a href="../{href_for(Path(TOP_INDEX_NAME))}">Back to main index</a></p>

<h1>{html_escape(folder_name)}</h1>

<div class="note">
    Open an email by clicking its subject. Attachments are listed here for context and are also linked from each email page.
</div>

<table>
<thead>
<tr>
    <th>No.</th>
    <th>Date</th>
    <th>From</th>
    <th>Subject</th>
    <th>Attachments</th>
</tr>
</thead>
<tbody>
{''.join(rows)}
</tbody>
</table>

</div>
</body>
</html>
"""


def render_top_index(folder_summaries):
    rows = []

    for item in folder_summaries:
        rows.append(
            f"""
            <tr>
                <td><a href="{href_for(item["folder_path"] / FOLDER_INDEX_NAME)}">{html_escape(item["folder_name"])}</a></td>
                <td>{item["count"]}</td>
            </tr>
            """
        )

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Email archive</title>
<style>
body {{
    font-family: Arial, Helvetica, sans-serif;
    margin: 0;
    background: #f4f4f4;
    color: #222;
}}
.container {{
    max-width: 900px;
    margin: 24px auto;
    background: white;
    border: 1px solid #d0d0d0;
    padding: 24px;
}}
h1 {{
    font-size: 26px;
    margin-top: 0;
}}
table {{
    border-collapse: collapse;
    width: 100%;
}}
th, td {{
    border: 1px solid #ddd;
    padding: 8px;
}}
th {{
    background: #eee;
    text-align: left;
}}
.note {{
    background: #fbfbfb;
    border: 1px solid #ddd;
    padding: 12px;
    margin-bottom: 20px;
}}
a {{
    color: #0645ad;
}}
</style>
</head>
<body>
<div class="container">

<h1>Email archive</h1>

<div class="note">
    Start here. Click a folder below, then click an email subject to read it.
    Each email page lists the attachments that belong to that email.
</div>

<table>
<thead>
<tr>
    <th>Folder</th>
    <th>Email count</th>
</tr>
</thead>
<tbody>
{''.join(rows)}
</tbody>
</table>

<p>Conversion log: <a href="{href_for(Path(LOG_NAME))}">{html_escape(LOG_NAME)}</a></p>

</div>
</body>
</html>
"""


# =========================
# MAIN
# =========================

def convert_archive():
    DEST.mkdir(parents=True, exist_ok=True)

    # Fresh log each run.
    log_path = DEST / LOG_NAME
    if log_path.exists():
        log_path.unlink()

    append_log(f"Source: {SOURCE}")
    append_log(f"Destination: {DEST}")
    append_log("")

    if not SOURCE.exists():
        raise FileNotFoundError(f"Source folder does not exist: {SOURCE}")

    msg_files = sorted(SOURCE.rglob("*.msg"))

    if not msg_files:
        append_log("No .msg files found.")
        print("No .msg files found.")
        return

    folders = {}

    for msg_path in msg_files:
        relative_folder = msg_path.parent.relative_to(SOURCE)
        folders.setdefault(relative_folder, []).append(msg_path)

    folder_summaries = []

    for relative_folder, files in sorted(folders.items(), key=lambda x: str(x[0]).lower()):
        output_folder = DEST / relative_folder
        output_folder.mkdir(parents=True, exist_ok=True)

        converted_emails = []

        # First pass: read metadata so we can sort by date.
        raw_items = []

        for msg_path in files:
            try:
                msg = extract_msg.Message(str(msg_path))

                display_date, sort_key, filename_date = normalise_date(getattr(msg, "date", None))

                raw_items.append({
                    "msg_path": msg_path,
                    "msg": msg,
                    "sort_key": sort_key,
                    "display_date": display_date,
                    "filename_date": filename_date,
                })

            except Exception:
                append_log(f"FAILED OPEN: {msg_path}")
                append_log(traceback.format_exc())
                append_log("")
                continue

        raw_items.sort(key=lambda item: (item["sort_key"], str(item["msg_path"]).lower()))

        for index, item in enumerate(raw_items, start=1):
            msg_path = item["msg_path"]
            msg = item["msg"]

            try:
                subject = getattr(msg, "subject", None) or "No subject"
                sender = getattr(msg, "sender", None) or ""
                to = getattr(msg, "to", None) or ""
                cc = getattr(msg, "cc", None) or ""

                base_name = safe_filename(f"{index:03} - {subject}")
                html_file = unique_path(output_folder / f"{base_name}.html")
                attachment_folder = output_folder / f"{html_file.stem}_attachments"

                attachments = []

                msg_attachments = getattr(msg, "attachments", []) or []

                if msg_attachments:
                    attachment_folder.mkdir(parents=True, exist_ok=True)

                    for att_index, attachment in enumerate(msg_attachments, start=1):
                        attachment_name = get_attachment_name(attachment, att_index)
                        target_path = unique_path(attachment_folder / attachment_name)

                        try:
                            attachment.save(
                                customPath=str(attachment_folder),
                                customFilename=target_path.name
                            )

                            attachments.append({
                                "name": target_path.name,
                                "path": target_path,
                                "relative_path": target_path.relative_to(output_folder),
                            })

                        except Exception:
                            append_log(f"FAILED ATTACHMENT: {msg_path} attachment {att_index}")
                            append_log(traceback.format_exc())
                            append_log("")

                email = {
                    "number": index,
                    "source": str(msg_path),
                    "subject": subject,
                    "sender": sender,
                    "to": to,
                    "cc": cc,
                    "display_date": item["display_date"],
                    "sort_key": item["sort_key"],
                    "html_file": html_file,
                    "attachments": attachments,
                    "body_html": get_message_body(msg),
                }

                email_html = render_email_page(email)
                write_text(html_file, email_html)

                converted_emails.append(email)

                append_log(f"OK: {msg_path} -> {html_file}")

            except Exception:
                append_log(f"FAILED CONVERT: {msg_path}")
                append_log(traceback.format_exc())
                append_log("")

            finally:
                try:
                    msg.close()
                except Exception:
                    pass

        folder_index_html = render_folder_index(
            folder_name=str(relative_folder) if str(relative_folder) != "." else SOURCE.name,
            emails=converted_emails,
        )

        write_text(output_folder / FOLDER_INDEX_NAME, folder_index_html)

        folder_summaries.append({
            "folder_name": str(relative_folder) if str(relative_folder) != "." else SOURCE.name,
            "folder_path": relative_folder,
            "count": len(converted_emails),
        })

    top_index_html = render_top_index(folder_summaries)
    write_text(DEST / TOP_INDEX_NAME, top_index_html)

    append_log("")
    append_log("Done.")

    print("Done.")
    print(f"Open this file:")
    print(DEST / TOP_INDEX_NAME)


if __name__ == "__main__":
    convert_archive()