import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tokens = json.loads((root / 'docs/flutter-theme-tokens.json').read_text(encoding='utf-8'))
lines = ['package bbs.binmt.cc', '', 'import androidx.compose.material3.*', 'import androidx.compose.ui.graphics.Color', '', '// Generated from the preserved Flutter AppTheme; do not redesign these tokens.', 'val originalColorSchemes = listOf(']
for row in tokens:
    method = 'darkColorScheme' if row['dark'] else 'lightColorScheme'
    lines.append('    ' + method + '(')
    for role, value in row['colors'].items():
        lines.append(f'        {role} = Color(0x{value:08X}),')
    lines.append(f"        background = Color(0x{row['colors']['surface']:08X}), onBackground = Color(0x{row['colors']['onSurface']:08X})")
    lines.append('    ),')
lines.append(')')
(root / 'app/src/main/java/bbs/binmt/cc/OriginalColors.kt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
