# Contributing to Nexus Photo & Document Optimizer

Thank you for your interest in contributing to **Nexus Photo & Document Optimizer**! We welcome contributions from developers, sysadmins, and municipal automation engineers worldwide.

---

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). Please treat all contributors with respect and kindness.

---

## How Can You Help?

There are many ways to contribute:
1. **Report Bugs**: Submit detailed bug reports using our [Issue Templates](https://github.com/Mandar023/Nexus-Photo-Optimizer/issues/new/choose).
2. **Feature Suggestions**: Propose new ideas, image codecs, or database integrations.
3. **Documentation & Guides**: Improve setup instructions, add Marathi/Hindi/regional localization, or create tutorials.
4. **Code Improvements**:
   - Enhance compression algorithms.
   - Add new vector format parsers (DWG, DXF, SVG).
   - Improve WPF UI responsiveness and animations.
   - Optimize SQL query parsing and schema extraction.

---

## Development Setup

1. **Fork and Clone**:
   ```bash
   git clone https://github.com/Mandar023/Nexus-Photo-Optimizer.git
   cd Nexus-Photo-Optimizer
   ```

2. **Environment Requirements**:
   - Windows 10 / 11 / Server 2016+ (x64)
   - PowerShell 5.1 (built into Windows) or PowerShell 7+
   - .NET Framework 4.7.2+

3. **Verifying Syntax**:
   Before submitting code, ensure zero AST parser syntax errors:
   ```powershell
   Get-ChildItem -Filter "*.ps1" | ForEach-Object {
       $errs = $null
       [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errs) | Out-Null
       if ($errs.Count -gt 0) {
           Write-Host "SYNTAX ERROR in $($_.Name): $($errs.Count) errors" -ForegroundColor Red
       } else {
           Write-Host "$($_.Name): OK" -ForegroundColor Green
       }
   }
   ```

---

## Commit Guidelines

Follow conventional commit formats:
- `feat: <description>` for new capabilities
- `fix: <description>` for bug fixes
- `docs: <description>` for documentation changes
- `perf: <description>` for performance improvements
- `refactor: <description>` for internal code cleanups

---

## Pull Request Process

1. Create a feature branch (`git checkout -b feature/amazing-improvement`).
2. Test your changes locally on multiple screen resolutions and DPI scaling settings.
3. Commit your changes (`git commit -m "feat: add support for XYZ"`).
4. Push to your branch (`git push origin feature/amazing-improvement`).
5. Open a Pull Request against the `main` branch with a clear description and screenshots.
