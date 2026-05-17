import sys
import re

with open('build.zig', 'r') as f:
    content = f.read()

content = re.sub(r'b\.cache_root = .*\n', '', content)

with open('build.zig', 'w') as f:
    f.write(content)
