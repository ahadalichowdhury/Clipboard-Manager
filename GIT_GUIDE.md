# Git Guide for Clipboard Manager

This guide provides step-by-step instructions for common Git operations in the Clipboard Manager project.

## Initial Setup

1. Clone the repository:

```bash
git clone https://github.com/ahadalichowdhury/Clipboard-Manager.git
cd Clipboard-Manager
```

2. Install GitHub CLI (if not installed):

```bash
brew install gh
gh auth login
```

## Daily Development Workflow

1. Check current status:

```bash
git status
```

2. Create a new feature branch:

```bash
git checkout -b feature/your-feature-name
```

3. Make changes and commit:

```bash
git add .
git commit -m "🎨 Your commit message"
```

4. Push changes:

```bash
git push origin feature/your-feature-name
```

## Creating a New Release

1. Build the DMG file:

```bash
./build_dmg.sh
```

2. Create and push a new tag:

```bash
git tag -a v1.0.1 -m "Release version 1.0.1"
git push origin v1.0.1
```

3. Create release with DMG file:

```bash
gh release create v1.0.1 \
  --title "Clipboard Manager v1.0.1" \
  --notes "Release notes here" \
  build/ClipboardManager.dmg
```

## Common Git Commands

### Branch Management

```bash
# List all branches
git branch

# Switch to a branch
git checkout branch-name

# Create and switch to new branch
git checkout -b new-branch-name

# Delete a branch
git branch -d branch-name
```

### Staging and Committing

```bash
# Add specific file
git add filename

# Add all changes
git add .

# Commit changes
git commit -m "Your message"

# Commit with emoji (recommended)
git commit -m "🎨 Format code"
git commit -m "🐛 Fix bug"
git commit -m "✨ Add new feature"
```

### Pushing and Pulling

```bash
# Push to remote
git push origin branch-name

# Pull latest changes
git pull origin branch-name

# Force push (use with caution)
git push -f origin branch-name
```

### Tag Management

```bash
# List all tags
git tag

# Create new tag
git tag -a v1.0.1 -m "Release version 1.0.1"

# Push tag to remote
git push origin v1.0.1
```

### Release Management

```bash
# Create new release with DMG
gh release create v1.0.1 \
  --title "Clipboard Manager v1.0.1" \
  --notes "Release notes here" \
  build/ClipboardManager.dmg

# List releases
gh release list

# View release details
gh release view v1.0.1
```

## Commit Message Guidelines

Use emojis to indicate the type of change:

- 🎨 `:art:` - Improving code format/structure
- 🐎 `:racehorse:` - Performance improvements
- 🚱 `:non-potable_water:` - Plugging memory leaks
- 📝 `:memo:` - Writing docs
- 🐛 `:bug:` - Fixing a bug
- 🔥 `:fire:` - Removing code or files
- 💚 `:green_heart:` - Fixing CI build
- ✅ `:white_check_mark:` - Adding tests
- 🔒 `:lock:` - Dealing with security
- ⬆️ `:arrow_up:` - Upgrading dependencies
- ⬇️ `:arrow_down:` - Downgrading dependencies
- 👕 `:shirt:` - Removing linter warnings

## Troubleshooting

1. If you get "tag exists locally but has not been pushed":

```bash
git push origin tag-name
```

2. If you need to update a release:

```bash
# Delete the release first
gh release delete v1.0.1

# Create new release
gh release create v1.0.1 --title "..." --notes "..." build/ClipboardManager.dmg
```

3. If you need to reset to a previous commit:

```bash
git reset --hard commit-hash
```

## Best Practices

1. Always create feature branches for new work
2. Use meaningful commit messages with emojis
3. Keep commits atomic and focused
4. Test changes before pushing
5. Update documentation when making changes
6. Keep the DMG file up to date with releases

## Need Help?

- Check GitHub documentation: https://docs.github.com
- Check GitHub CLI documentation: https://cli.github.com
- Ask in project issues or discussions
