"""Moves the `footer` argument above `children` in every AuthPage call so the
children list is the last argument (sort_child_properties_last)."""

import pathlib
import sys

FILES = [
    "lib/ui/auth/account_type_screen.dart",
    "lib/ui/auth/auth_error_screen.dart",
    "lib/ui/auth/create_account_screen.dart",
    "lib/ui/auth/forgot_password_screen.dart",
    "lib/ui/auth/profile_basics_screen.dart",
    "lib/ui/auth/profile_photo_screen.dart",
    "lib/ui/auth/reset_password_screen.dart",
    "lib/ui/auth/select_sports_screen.dart",
    "lib/ui/auth/setup_complete_screen.dart",
    "lib/ui/auth/sign_in_screen.dart",
    "lib/ui/auth/sports_levels_screen.dart",
    "lib/ui/auth/terms_screen.dart",
    "lib/ui/auth/verify_email_screen.dart",
    "lib/ui/auth/welcome_screen.dart",
]

CHILDREN_OPEN = "      children: [\n"
CHILDREN_CLOSE = "\n      ],\n"
CALL_END = "\n    );"
root = pathlib.Path("/home/til3fishnix001/Desktop/sportika_2026@")

changed = []
for name in FILES:
    path = root / name
    text = path.read_text()
    call = text.index("return AuthPage(")
    start = text.index(CHILDREN_OPEN, call)
    close = text.index(CHILDREN_CLOSE, start) + len(CHILDREN_CLOSE)
    end = text.index(CALL_END, close)
    children_block = text[start:close]
    after = text[close:end]  # footer argument, no trailing newline
    if not after.lstrip().startswith("footer:"):
        sys.exit(f"unexpected arguments after children in {name}: {after[:60]!r}")
    # children_block keeps its inner newlines but loses the trailing one, which
    # is supplied again by text[end:] (the call's closing "    );" line).
    path.write_text(
        text[:start] + after + "\n" + children_block[:-1] + text[end:]
    )
    changed.append(name)

print(f"reordered {len(changed)} files: " + ", ".join(changed))
