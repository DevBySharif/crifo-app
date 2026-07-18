import re

with open(r'lib\features\tv\tv_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: rename _showDudeSubChannels to _showDudeSubChannelsSheet
content = content.replace('_showDudeSubChannels(ch)', '_showDudeSubChannelsSheet(ch)')

# Fix 2: Fix the broken count text (PowerShell ate $count -> became empty string)
# The bad line looks like: count > 99 ? '99+' : '\',
# Replace with: count > 99 ? '99+' : '$count',
bad = "count > 99 ? '99+' : '\\','
good = "count > 99 ? '99+' : '$count',"
content = content.replace(bad, good)

# Also fix any variant
bad2 = "count > 99 ? '99+' : '\\',"
content = content.replace(bad2, good)

with open(r'lib\features\tv\tv_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('Fixes applied')

# Verify
with open(r'lib\features\tv\tv_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines[1950:1960], start=1951):
    print(f'{i}: {line}', end='')
