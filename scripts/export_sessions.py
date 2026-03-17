#!/usr/bin/env python3
"""Export Cursor agent transcript JSONL files to Markdown format."""
import json
import re
import datetime
from pathlib import Path

TRANSCRIPTS_DIR = Path("/home/ceceadmin/.cursor/projects/mnt-ai-infra-users-wnd-workspace-execute-guofan/agent-transcripts")
OUTPUT_DIR = Path("/mnt/ai-infra/users/wnd/workspace/execute/guofan/clingo/sessions")

ALREADY_EXPORTED = {
    "0302905e-d96a-4fac-85b9-6f6b45736508",
    "bcbf1eef-6b40-4503-b6ea-f80f36675c95",
    "ba78a303-5c92-48e8-acd5-1625fb4fc9df",
    "29cd9290-10b4-41e6-ae9e-f449267930b7",
    "ce316707-7c67-44c5-96a3-f11ff673c211",
    "19885ffa-239d-49e3-8b0d-a7a4f0d1b9d1",
}

ARCHIVED = {
    "18ed079d-e7e3-4c18-a851-eda126598ae1",
    "4c28517a-b8bb-40a1-a9f8-d2601c5921bf",
    "fd88f0c5-c792-4fb6-9307-7371212e431c",
    "db6c888d-5d63-4bfd-99a9-4d9bbf6f78b0",
    "e2c18b49-f6cf-43f0-b15b-19cd36c73a68",
    "e46d2efe-a04a-4828-bd58-3f983fac5fc3",
    "875a2d8d-dd04-45e9-b9dd-750695c15187",
}

SKIP_UUIDS = ALREADY_EXPORTED | ARCHIVED
CUTOFF_DATE = datetime.date(2026, 3, 14)

def extract_user_text(content_list):
    texts = []
    for item in content_list:
        if item.get("type") == "text":
            text = item["text"]
            if "<user_query>" in text:
                match = re.search(r"<user_query>(.*?)</user_query>", text, re.DOTALL)
                if match:
                    text = match.group(1).strip()
                else:
                    for tag in ["user_info","system_reminder","attached_files","git_status",
                                "open_and_recently_viewed_files","task_notification",
                                "agent_transcripts","rules","agent_skills","image_files","external_links"]:
                        text = re.sub(f"<{tag}>.*?</{tag}>", "", text, flags=re.DOTALL)
                    text = text.strip()
            else:
                text = re.sub(r"<[a-z_]+>.*?</[a-z_]+>", "", text, flags=re.DOTALL).strip()
            if text:
                texts.append(text)
    return "\n\n".join(texts)

def extract_assistant_text(content_list):
    texts = []
    for item in content_list:
        if item.get("type") == "text":
            text = item["text"].strip()
            if text:
                texts.append(text)
    return "\n\n".join(texts)

def generate_title(msg):
    first_line = msg.strip().split("\n")[0].strip()
    first_line = re.sub(r"@[\w/.\-]+", "", first_line)
    first_line = re.sub(r"https?://\S+", "", first_line)
    first_line = re.sub(r"\s+", " ", first_line).strip()
    if len(first_line) > 70:
        first_line = first_line[:67] + "..."
    return first_line if first_line else "Cursor Session"

def make_filename(uuid_short, dt, first_user_msg):
    date_str = dt.strftime("%Y%m%d")
    msg = first_user_msg.strip().split("\n")[0].strip()
    msg = re.sub(r"@[\w/.\-]+", "", msg)
    msg = re.sub(r"https?://\S+", "", msg)
    msg = re.sub(r"[^\w\s\u4e00-\u9fff]", " ", msg)
    slug = re.sub(r"\s+", "_", msg.strip())[:40].strip("_").lower()
    return f"{date_str}_{uuid_short}_{slug}.md"

def export_session(uuid, jsonl_file, session_dt):
    messages = []
    with open(jsonl_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                role = data.get("role", "")
                content = data.get("message", {}).get("content", [])
                if role == "user":
                    text = extract_user_text(content)
                    if text:
                        messages.append(("user", text))
                elif role == "assistant":
                    text = extract_assistant_text(content)
                    if text:
                        messages.append(("assistant", text))
            except Exception:
                pass

    if not messages:
        return None

    first_user_msg = next((t for r, t in messages if r == "user"), "")
    if not first_user_msg:
        return None

    title = generate_title(first_user_msg)
    dt_str = session_dt.strftime("%Y/%-m/%-d at GMT+8 %H:%M:%S")

    lines = [f"# {title}", f"_Exported on {dt_str} from Cursor (transcript)_", "", "---", ""]
    for role, text in messages:
        label = "**User**" if role == "user" else "**Cursor**"
        lines.extend([label, "", text, "", "---", ""])

    filename = make_filename(uuid[:8], session_dt, first_user_msg)
    return filename, "\n".join(lines)

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    entries = []
    for uuid_dir in TRANSCRIPTS_DIR.iterdir():
        if uuid_dir.is_dir():
            jsonl = uuid_dir / f"{uuid_dir.name}.jsonl"
            if jsonl.exists():
                mtime = uuid_dir.stat().st_mtime
                dt = datetime.datetime.fromtimestamp(mtime)
                entries.append((dt, uuid_dir.name, jsonl))
    entries.sort()

    exported_count = 0
    skipped_count = 0
    for dt, uuid, jsonl_file in entries:
        if dt.date() >= CUTOFF_DATE:
            continue
        if uuid in SKIP_UUIDS:
            reason = "already_exported" if uuid in ALREADY_EXPORTED else "archived"
            print(f"SKIP [{reason}]: {uuid[:8]} ({dt.strftime('%m-%d %H:%M')})")
            skipped_count += 1
            continue
        result = export_session(uuid, jsonl_file, dt)
        if result is None:
            print(f"EMPTY: {uuid[:8]} ({dt.strftime('%m-%d %H:%M')})")
            continue
        filename, content = result
        output_path = OUTPUT_DIR / filename
        if output_path.exists():
            print(f"EXISTS: {filename}")
            continue
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"EXPORTED: {filename}")
        exported_count += 1

    print(f"\nDone: {exported_count} exported, {skipped_count} skipped")

if __name__ == "__main__":
    main()
