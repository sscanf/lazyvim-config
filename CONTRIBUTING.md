# Contributing to LazyVim Configuration

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## 🤝 How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with:

1. **Clear title**: Describe the issue briefly
2. **Description**: What happened vs. what you expected
3. **Steps to reproduce**: How to trigger the bug
4. **Environment**:
   - Neovim version (`nvim --version`)
   - OS and version
   - Plugin manager state (`:Lazy`)
5. **Screenshots/logs**: If applicable

Example:
```
Title: Remote debugging fails on Ubuntu 22.04

Description:
When I run :CMakeDeploy, I get "sshpass not found" error even though it's installed.

Steps to reproduce:
1. Install on Ubuntu 22.04
2. Run :CMakeDeploy
3. See error

Environment:
- Neovim v0.9.5
- Ubuntu 22.04
- All plugins up to date

Error log:
[paste error log here]
```

### Suggesting Features

Feature requests are welcome! Please include:

1. **Use case**: Why is this feature needed?
2. **Proposed solution**: How should it work?
3. **Alternatives**: Other ways you've considered
4. **Examples**: Similar features in other tools

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**
4. **Test thoroughly**:
   - Test on a clean Neovim installation
   - Verify no breaking changes
   - Check for Lua errors (`:checkhealth`)
5. **Commit with clear messages**:
   ```bash
   git commit -m "feat(dap): add support for cross-compilation targets"
   ```
6. **Push and create PR**

### Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat(scope):` New feature
- `fix(scope):` Bug fix
- `docs(scope):` Documentation changes
- `refactor(scope):` Code refactoring
- `perf(scope):` Performance improvement
- `test(scope):` Test additions
- `chore(scope):` Maintenance tasks

**Scopes**:
- `dap`: Debugging functionality
- `lsp`: Language server features
- `ui`: User interface changes
- `cmake`: CMake integration
- `git`: Git-related plugins
- `ai`: AI/Copilot features

Examples:
```bash
feat(dap): add support for Rust remote debugging
fix(cmake): correct deployment path parsing for nested projects
docs(readme): add troubleshooting section for macOS
refactor(dap): extract SSH connection logic to separate module
```

## 🧪 Testing Your Changes

### Local Testing

1. **Backup your current config**:
   ```bash
   mv ~/.config/nvim ~/.config/nvim.backup
   mv ~/.local/share/nvim ~/.local/share/nvim.backup
   ```

2. **Clone your fork**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/lazyvim-config.git ~/.config/nvim
   cd ~/.config/nvim
   git checkout your-feature-branch
   ```

3. **Start Neovim and test**:
   ```bash
   nvim
   ```

4. **Check for errors**:
   ```vim
   :checkhealth
   :Lazy
   :messages
   ```

### Testing Remote Debugging Changes

If you're modifying `lua/plugins/dap/remote.lua`:

1. Set up a test environment with SSH access
2. Create a minimal CMake project
3. Test the full workflow:
   - `:CMakeBuild`
   - `:CMakeDeploy`
   - `<leader>dR` (remote debug)
4. Verify:
   - Files deploy correctly
   - gdbserver starts
   - Breakpoints work
   - Variables display correctly
   - Remote output appears in console

## 📝 Code Style

### Lua Code

- Use 2 spaces for indentation
- Use descriptive variable names
- Add comments for complex logic
- Keep functions focused and small
- Use local variables when possible

Example:
```lua
-- Good
local function deploy_files_with_tar(files, destination)
  local tar_cmd = string.format("tar czf - %s | ssh %s 'tar xzf - -C %s'",
    table.concat(files, " "),
    ssh_host,
    destination
  )
  return vim.fn.system(tar_cmd)
end

-- Avoid
function d(f,d) local c=string.format("tar czf - %s | ssh %s 'tar xzf - -C %s'",table.concat(f," "),h,d) return vim.fn.system(c) end
```

### Documentation

- Update README.md if adding new features
- Add comments to complex code
- Include examples for new functionality
- Update keymaps documentation if changing bindings

## 🎯 Areas for Contribution

### High Priority

- [ ] Support for more architectures (ARM, RISC-V)
- [ ] Windows support for remote debugging
- [ ] Better error messages and diagnostics
- [ ] Performance optimizations for large projects
- [ ] Unit tests for deployment logic

### Medium Priority

- [ ] Integration with Docker containers
- [ ] Support for multiple remote targets
- [ ] Configuration presets for common setups
- [ ] Better CMake preset detection
- [ ] Screenshot/video documentation

### Low Priority

- [ ] Support for other build systems (Meson, Bazel)
- [ ] Integration with CI/CD pipelines
- [ ] Plugin for VSCode Remote-SSH compatibility
- [ ] Telemetry for debugging issues

## 🔒 Security

- **Never commit passwords or secrets** in code or docs
- Use environment variables or CMakePresets.json for credentials
- Be careful with `vim.fn.system()` to avoid command injection
- Review SSH commands for security issues

## ❓ Questions?

- Open a [Discussion](https://github.com/sscanf/lazyvim-config/discussions) for general questions
- Use [Issues](https://github.com/sscanf/lazyvim-config/issues) for bugs/features
- Check existing issues before creating new ones

## 📜 License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT).

---

Thank you for contributing! 🚀
