#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/sscanf/lazyvim-config.git"
NVIM_CONFIG_DIR="$HOME/.config/nvim"
NVIM_DATA_DIR="$HOME/.local/share/nvim"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"

# Utility functions
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect package manager
detect_package_manager() {
    if command_exists apt; then
        echo "apt"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists yum; then
        echo "yum"
    elif command_exists pacman; then
        echo "pacman"
    elif command_exists brew; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Install system dependencies
install_dependencies() {
    print_header "Installing System Dependencies"

    local pkg_manager=$(detect_package_manager)

    if [ "$pkg_manager" == "unknown" ]; then
        print_warning "Could not detect package manager. Please install dependencies manually:"
        echo "  - neovim (>= 0.9.0)"
        echo "  - git"
        echo "  - fd (fd-find)"
        echo "  - ripgrep"
        echo "  - nodejs (for LSP and Copilot)"
        echo ""
        echo "Optional for remote debugging:"
        echo "  - sshpass"
        echo "  - gdb"
        echo "  - rsync"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        return
    fi

    print_info "Detected package manager: $pkg_manager"

    case $pkg_manager in
        apt)
            print_info "Installing dependencies with apt..."
            sudo apt update
            sudo apt install -y \
                neovim \
                git \
                fd-find \
                ripgrep \
                nodejs \
                npm \
                sshpass \
                gdb \
                rsync \
                cmake \
                clang

            # fd-find symlink on Ubuntu/Debian
            if ! command_exists fd && command_exists fdfind; then
                print_info "Creating fd symlink..."
                sudo ln -sf $(which fdfind) /usr/local/bin/fd
            fi
            ;;
        dnf|yum)
            print_info "Installing dependencies with $pkg_manager..."
            sudo $pkg_manager install -y \
                neovim \
                git \
                fd-find \
                ripgrep \
                nodejs \
                npm \
                sshpass \
                gdb \
                rsync \
                cmake \
                clang
            ;;
        pacman)
            print_info "Installing dependencies with pacman..."
            sudo pacman -S --noconfirm \
                neovim \
                git \
                fd \
                ripgrep \
                nodejs \
                npm \
                sshpass \
                gdb \
                rsync \
                cmake \
                clang
            ;;
        brew)
            print_info "Installing dependencies with brew..."
            brew install \
                neovim \
                git \
                fd \
                ripgrep \
                node \
                sshpass \
                gdb \
                rsync \
                cmake \
                llvm
            ;;
    esac

    print_success "System dependencies installed"
}

# Backup existing configuration
backup_existing_config() {
    print_header "Backing Up Existing Configuration"

    local needs_backup=false

    if [ -d "$NVIM_CONFIG_DIR" ]; then
        print_info "Backing up $NVIM_CONFIG_DIR..."
        mv "$NVIM_CONFIG_DIR" "${NVIM_CONFIG_DIR}${BACKUP_SUFFIX}"
        print_success "Config backed up to ${NVIM_CONFIG_DIR}${BACKUP_SUFFIX}"
        needs_backup=true
    fi

    if [ -d "$NVIM_DATA_DIR" ]; then
        print_info "Backing up $NVIM_DATA_DIR..."
        mv "$NVIM_DATA_DIR" "${NVIM_DATA_DIR}${BACKUP_SUFFIX}"
        print_success "Data backed up to ${NVIM_DATA_DIR}${BACKUP_SUFFIX}"
        needs_backup=true
    fi

    if [ "$needs_backup" = false ]; then
        print_info "No existing configuration found. Starting fresh."
    fi
}

# Clone repository
clone_repository() {
    print_header "Cloning LazyVim Configuration"

    print_info "Cloning from $REPO_URL..."
    git clone "$REPO_URL" "$NVIM_CONFIG_DIR"

    print_success "Repository cloned successfully"
}

# Check Neovim version
check_neovim_version() {
    print_header "Checking Neovim Version"

    if ! command_exists nvim; then
        print_error "Neovim is not installed!"
        exit 1
    fi

    local nvim_version=$(nvim --version | head -n 1 | grep -oP '\d+\.\d+\.\d+')
    print_info "Neovim version: $nvim_version"

    # Check if version >= 0.9.0
    local required_version="0.9.0"
    if printf '%s\n%s\n' "$required_version" "$nvim_version" | sort -V -C; then
        print_success "Neovim version is compatible"
    else
        print_warning "Neovim version $nvim_version is older than recommended $required_version"
        print_warning "Some features may not work correctly"
    fi
}

# Setup complete message
show_completion_message() {
    print_header "Installation Complete!"

    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║  🎉 LazyVim Configuration installed successfully!            ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

📋 Next Steps:

1. Start Neovim:
   $ nvim

2. Wait for plugins to install automatically
   (LazyVim will install everything on first launch)

3. For C/C++ remote debugging, configure your project:
   Create or edit CMakePresets.json in your project root:

   {
     "configurePresets": [{
       "cacheVariables": {
         "REMOTE_SSH_HOST": "192.168.1.100",
         "REMOTE_SSH_PORT": "22",
         "REMOTE_SSH_PASS": "your_password",
         "REMOTE_GDBSERVER_PORT": "10000",
         "LOCAL_GDB_PATH": "/usr/bin/gdb"
       }
     }]
   }

4. Basic workflow:
   :CMakeBuild          - Build your project
   :CMakeDeploy         - Deploy to remote
   <leader>dR           - Start remote debugging

📚 Documentation:
   README: ~/.config/nvim/README.md
   Or visit: https://github.com/sscanf/lazyvim-config

⌨️  Key Mappings:
   <leader>     = Space
   <leader>dR   = Remote debug
   <leader>du   = Toggle DAP UI
   <C-\>        = Toggle terminal
   <leader>ss   = Search sessions

🔧 Useful Commands:
   :Mason              - Install LSP servers
   :Lazy               - Manage plugins
   :checkhealth        - Check Neovim health

Happy coding! 🚀
EOF
}

# Interactive mode
run_interactive() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║              LazyVim Configuration Installer                  ║
║                                                               ║
║  Advanced Neovim setup for C/C++ development with            ║
║  remote debugging, CMake integration, and AI assistance       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo ""

    # Check dependencies option
    print_info "This installer will:"
    echo "  1. Backup existing Neovim configuration"
    echo "  2. Install system dependencies"
    echo "  3. Clone LazyVim configuration"
    echo "  4. Set up everything automatically"
    echo ""

    read -p "Do you want to install system dependencies? (recommended) (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        SKIP_DEPENDENCIES=true
    else
        SKIP_DEPENDENCIES=false
    fi

    echo ""
    read -p "Continue with installation? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_warning "Installation cancelled"
        exit 0
    fi

    # Run installation
    if [ "$SKIP_DEPENDENCIES" = false ]; then
        install_dependencies
    else
        print_warning "Skipping system dependencies installation"
    fi

    backup_existing_config
    clone_repository
    check_neovim_version
    show_completion_message
}

# Non-interactive mode
run_non_interactive() {
    print_info "Running in non-interactive mode..."
    install_dependencies
    backup_existing_config
    clone_repository
    check_neovim_version
    show_completion_message
}

# Main execution
main() {
    if [ "$1" == "--non-interactive" ] || [ "$1" == "-n" ]; then
        run_non_interactive
    else
        run_interactive
    fi
}

# Run installer
main "$@"
