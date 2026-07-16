#!/usr/bin/env python3
"""Import and normalize the pinned exercises dataset for Trainote.

The generated catalog is committed to the app bundle. Runtime code never calls
the dataset repository or the optional local translation endpoint.
"""

import argparse
import json
import math
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Dict, Iterable, List, Sequence


SOURCE_SHA = "118e4bd6b14da6df0e36605d7169b65db18389a4"
SOURCE_URL = (
    "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/"
    f"{SOURCE_SHA}/data/exercises.json"
)
SOURCE_REPOSITORY = "https://github.com/hasaneyldrm/exercises-dataset"
EXPECTED_COUNT = 1324
TRANSLATION_BATCH_SIZE = 20
FORBIDDEN_OUTPUT_KEYS = {"image", "gif_url", "media_id", "attribution", "created_at"}
CURATED_NAME_OVERRIDES = {
    "0284": "驴式提踵",
    "1275": "落差俯卧撑",
    "0285": "哑铃交替肱二头肌弯举",
    "2403": "使用臂托板的哑铃交替肱二头肌弯举",
    "1646": "哑铃交替锤式牧师凳弯举",
    "1647": "哑铃交替牧师凳弯举",
    "1648": "哑铃交替坐姿锤式弯举",
    "0286": "哑铃交替侧向推举",
    "1649": "健身球抬腿哑铃交替弯举",
    "1650": "健身球坐姿哑铃交替弯举",
    "2137": "哑铃阿诺德推举",
    "0287": "哑铃阿诺德推举（二）",
    "0288": "哑铃环绕上拉",
    "0289": "哑铃卧推",
    "0290": "哑铃长凳坐姿推举",
    "0291": "哑铃凳上深蹲",
    "0293": "哑铃俯身划船",
    "1651": "哑铃弯举弓步保龄球式动作",
    "1652": "健身球抬腿哑铃弯举",
    "1653": "鹤立姿哑铃弯举",
}

ROOT = Path(__file__).resolve().parents[1]
NAMES_PATH = ROOT / "Data" / "ExerciseNames.zh.json"
OUTPUT_PATH = ROOT / "Trainote" / "Resources" / "ExerciseCatalog.json"


def fetch_json(url: str, timeout: int = 60):
    request = urllib.request.Request(url, headers={"User-Agent": "Trainote-importer/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def validate_source(records: object) -> List[dict]:
    if not isinstance(records, list):
        raise ValueError("动作数据根节点必须是数组")
    if len(records) != EXPECTED_COUNT:
        raise ValueError(f"动作数量应为 {EXPECTED_COUNT}，实际为 {len(records)}")

    ids = [record.get("id") for record in records]
    if any(not isinstance(value, str) or not value for value in ids):
        raise ValueError("存在无效动作 ID")
    if len(set(ids)) != EXPECTED_COUNT:
        raise ValueError("动作 ID 不唯一")

    required = {
        "id",
        "name",
        "body_part",
        "equipment",
        "target",
        "muscle_group",
        "secondary_muscles",
        "instructions",
        "instruction_steps",
    }
    for record in records:
        missing = required.difference(record)
        if missing:
            raise ValueError(f"动作 {record.get('id')} 缺少字段：{sorted(missing)}")
        for language in ("en", "zh"):
            if not record["instructions"].get(language):
                raise ValueError(f"动作 {record['id']} 缺少 {language} 说明")
            if not record["instruction_steps"].get(language):
                raise ValueError(f"动作 {record['id']} 缺少 {language} 分步说明")

    return records


def chunks(values: Sequence[dict], size: int) -> Iterable[Sequence[dict]]:
    for index in range(0, len(values), size):
        yield values[index : index + size]


def parse_json_object(text: str) -> Dict[str, str]:
    text = text.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        text = "\n".join(lines[1:-1]).strip()
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("本地模型没有返回 JSON 对象")
    value = json.loads(text[start : end + 1])
    if not isinstance(value, dict):
        raise ValueError("本地模型返回值不是对象")
    return {str(key): str(name).strip() for key, name in value.items()}


def translate_batch(
    batch: Sequence[dict], endpoint: str, model: str, retries: int = 3
) -> Dict[str, str]:
    source = [{"id": item["id"], "name": item["name"]} for item in batch]
    ids = [item["id"] for item in batch]
    prompt = (
        "你是健身动作术语翻译员。把输入中的英文健身动作名翻译为简洁、专业、自然的简体中文。"
        "保留左右、器械、姿势和单双侧等关键信息。只返回一个 JSON 对象，键必须是原 id，值必须是中文动作名；"
        "不要 Markdown，不要解释，不要遗漏。输入："
        + json.dumps(source, ensure_ascii=False)
    )
    body = json.dumps(
        {
            "model": model,
            "messages": [
                {
                    "role": "system",
                    "content": "只输出严格 JSON。动作术语准确优先于逐字翻译。",
                },
                {"role": "user", "content": prompt},
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "exercise_name_translations",
                    "strict": True,
                    "schema": {
                        "type": "object",
                        "properties": {
                            item_id: {"type": "string", "minLength": 1}
                            for item_id in ids
                        },
                        "required": ids,
                        "additionalProperties": False,
                    },
                },
            },
            "temperature": 0,
            "max_tokens": 3000,
            "stream": False,
        }
    ).encode("utf-8")

    for attempt in range(1, retries + 1):
        try:
            request = urllib.request.Request(
                endpoint,
                data=body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=300) as response:
                payload = json.load(response)
            message = payload["choices"][0]["message"]
            content = message.get("content") or message.get("reasoning_content") or ""
            if not content:
                raise ValueError(
                    "本地模型返回空内容，"
                    f"finish_reason={payload['choices'][0].get('finish_reason')}，"
                    f"usage={payload.get('usage')}"
                )
            translated = parse_json_object(content)
            expected_ids = {item["id"] for item in batch}
            if set(translated) != expected_ids:
                missing = expected_ids.difference(translated)
                extra = set(translated).difference(expected_ids)
                raise ValueError(f"翻译 ID 不匹配，缺失={sorted(missing)}，多余={sorted(extra)}")
            if any(not name for name in translated.values()):
                raise ValueError("翻译结果包含空名称")
            return translated
        except (urllib.error.URLError, KeyError, ValueError, json.JSONDecodeError) as error:
            if attempt == retries:
                raise RuntimeError(f"本地翻译失败：{error}") from error
            time.sleep(attempt * 2)

    raise RuntimeError("本地翻译失败")


def load_names() -> Dict[str, str]:
    if not NAMES_PATH.exists():
        return dict(CURATED_NAME_OVERRIDES)
    with NAMES_PATH.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("中文名称映射必须是 JSON 对象")
    names = {str(key): str(name).strip() for key, name in value.items()}
    names.update(CURATED_NAME_OVERRIDES)
    return names


def save_names(names: Dict[str, str]) -> None:
    NAMES_PATH.parent.mkdir(parents=True, exist_ok=True)
    with NAMES_PATH.open("w", encoding="utf-8") as handle:
        json.dump(dict(sorted(names.items())), handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def ensure_translations(
    records: Sequence[dict], names: Dict[str, str], endpoint: str, model: str
) -> Dict[str, str]:
    missing = [record for record in records if not names.get(record["id"])]
    total_batches = math.ceil(len(missing) / TRANSLATION_BATCH_SIZE) if missing else 0
    for batch_index, batch in enumerate(
        chunks(missing, TRANSLATION_BATCH_SIZE), start=1
    ):
        print(f"翻译动作名 {batch_index}/{total_batches}...", flush=True)
        names.update(translate_batch(batch, endpoint, model))
        save_names(names)
    return names


def normalize(records: Sequence[dict], names: Dict[str, str]) -> dict:
    missing = [record["id"] for record in records if not names.get(record["id"])]
    if missing:
        raise ValueError(f"缺少 {len(missing)} 个中文动作名；请使用 --translate-missing")

    exercises = []
    for record in records:
        exercises.append(
            {
                "id": record["id"],
                "nameEn": record["name"].strip(),
                "nameZh": names[record["id"]].strip(),
                "bodyPart": record["body_part"].strip(),
                "equipment": record["equipment"].strip(),
                "target": record["target"].strip(),
                "muscleGroup": record["muscle_group"].strip(),
                "secondaryMuscles": record["secondary_muscles"],
                "instructionsEn": record["instructions"]["en"].strip(),
                "instructionsZh": record["instructions"]["zh"].strip(),
                "stepsEn": record["instruction_steps"]["en"],
                "stepsZh": record["instruction_steps"]["zh"],
            }
        )

    return {
        "source": {
            "repository": SOURCE_REPOSITORY,
            "commit": SOURCE_SHA,
            "license": "MIT (code, dataset structure, metadata and instruction text only)",
        },
        "exercises": exercises,
    }


def validate_output(catalog: dict) -> None:
    exercises = catalog.get("exercises", [])
    if len(exercises) != EXPECTED_COUNT:
        raise ValueError("规范化动作数量错误")
    if len({item["id"] for item in exercises}) != EXPECTED_COUNT:
        raise ValueError("规范化动作 ID 不唯一")
    serialized = json.dumps(catalog, ensure_ascii=False)
    for key in FORBIDDEN_OUTPUT_KEYS:
        if f'"{key}"' in serialized:
            raise ValueError(f"输出意外包含媒体或无关字段：{key}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--translate-missing", action="store_true")
    parser.add_argument(
        "--endpoint",
        default="http://127.0.0.1:1234/v1/chat/completions",
        help="OpenAI-compatible local chat completions endpoint",
    )
    parser.add_argument("--model", default="qwen/qwen3.6-35b-a3b")
    args = parser.parse_args()

    records = validate_source(fetch_json(SOURCE_URL))
    names = load_names()
    if args.translate_missing:
        names = ensure_translations(records, names, args.endpoint, args.model)
    save_names(names)

    catalog = normalize(records, names)
    validate_output(catalog)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")

    print(f"已生成 {OUTPUT_PATH}，共 {len(catalog['exercises'])} 个动作")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)
