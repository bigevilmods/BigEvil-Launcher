"""Build the public release index consumed by the launcher."""

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import unquote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


REPOSITORY = re.compile(r"[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+")
MAX_RESPONSE = 2 * 1024 * 1024


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def repository_url(value):
    if not isinstance(value, str):
        return None
    url = urlsplit(value)
    if url.scheme not in {"http", "https"} or url.netloc.lower() != "github.com":
        return None
    slug = unquote(url.path).strip("/").removesuffix(".git")
    return slug if REPOSITORY.fullmatch(slug) else None


def fetch_release(repository, token):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "BigEvil-Launcher-Release-Index",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(
        f"https://api.github.com/repos/{repository}/releases/latest",
        headers=headers,
    )
    try:
        with build_opener(NoRedirects()).open(request, timeout=20) as response:
            body = response.read(MAX_RESPONSE + 1)
    except HTTPError as error:
        if error.code == 404:
            return None
        raise RuntimeError(f"{repository}: GitHub HTTP {error.code}") from None
    if len(body) > MAX_RESPONSE:
        raise RuntimeError(f"{repository}: release metadata is too large")
    data = json.loads(body)
    if data.get("draft") or data.get("prerelease"):
        return None
    if not isinstance(data.get("tag_name"), str) or not isinstance(data.get("assets"), list):
        raise RuntimeError(f"{repository}: invalid release metadata")
    return {
        "tag_name": data["tag_name"],
        "published_at": data.get("published_at"),
        "assets": [
            {
                field: asset.get(field)
                for field in ("id", "name", "state", "size", "digest", "browser_download_url")
            }
            for asset in data["assets"]
            if asset.get("state") == "uploaded"
        ],
    }


def build_index(catalog, launcher, token):
    repositories = {launcher.lower(): launcher}
    for item in catalog:
        repository = repository_url(item.get("repositoryUrl")) or repository_url(
            item.get("downloadUrl")
        )
        if repository:
            repositories.setdefault(repository.lower(), repository)

    releases = {}
    for key, repository in sorted(repositories.items()):
        release = fetch_release(repository, token)
        if release is None and token and key != launcher.lower():
            # An installation token can have narrower visibility than a public request.
            release = fetch_release(repository, None)
        releases[key] = release
    return {
        "schema": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "repositories": releases,
    }


if __name__ == "__main__":
    launcher = os.environ["GITHUB_REPOSITORY"]
    if not REPOSITORY.fullmatch(launcher):
        raise SystemExit("Invalid launcher repository")
    catalog = json.loads(Path("catalog.json").read_text(encoding="utf-8"))
    index = build_index(catalog, launcher, os.environ.get("RELEASE_INDEX_TOKEN"))
    output = json.dumps(index, ensure_ascii=False, indent=2) + "\n"
    if len(output.encode("utf-8")) > MAX_RESPONSE:
        raise SystemExit("Release index is too large")
    Path(sys.argv[1]).write_text(output, encoding="utf-8")
