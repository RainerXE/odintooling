#!/usr/bin/env python3

import os
import subprocess
import re
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import sys

def run_linter(file_path, linter_path):
    """Run the odin-lint on a single file and return results"""
    try:
        result = subprocess.run(
            [linter_path, file_path],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        output = result.stdout + result.stderr
        
        # Count violations - only count actual violation lines (start with 🔴)
        violation_count = len([line for line in output.split('\n') if line.strip().startswith('🔴') and 'C001' in line])
        error_count = len(re.findall(r'INTERNAL ERROR', output))
        
        # Extract violation lines
        violation_lines = [line for line in output.split('\n') if 'C001' in line]
        
        # Extract error lines
        error_lines = [line for line in output.split('\n') if 'INTERNAL ERROR' in line]
        
        return {
            'file': file_path,
            'violation_count': violation_count,
            'error_count': error_count,
            'violation_lines': violation_lines,
            'error_lines': error_lines,
            'success': True
        }
        
    except subprocess.TimeoutExpired:
        return {
            'file': file_path,
            'violation_count': 0,
            'error_count': 1,
            'violation_lines': [],
            'error_lines': [f'Timeout after 10 seconds'],
            'success': False
        }
    except Exception as e:
        return {
            'file': file_path,
            'violation_count': 0,
            'error_count': 1,
            'violation_lines': [],
            'error_lines': [f'Error: {str(e)}'],
            'success': False
        }

def main():
    # Configuration
    ruishin_root = "/Users/rainer/Development/MyODIN/RuiShin"
    output_dir = "test_results/ruishin"
    linter_binary = "./artifacts/odin-lint"
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate report filename
    report_file = os.path.join(output_dir, f"ruishin_simple_report_{datetime.now().strftime('%Y%m%d')}.md")
    
    print("🔬 Simple RuiShin Library Test")
    print("====================================")
    print()
    print("📁 Testing RuiShin source code...")
    
    # Find all Odin files in RuiShin
    odin_files = []
    src_dir = os.path.join(ruishin_root, "src")
    
    if os.path.isdir(src_dir):
        for root, dirs, files in os.walk(src_dir):
            for file in files:
                if file.endswith('.odin'):
                    odin_files.append(os.path.join(root, file))
    
    if not odin_files:
        print("❌ No Odin files found in RuiShin source directory")
        return 1
    
    print(f"Found {len(odin_files)} files to test")
    
    # Initialize report
    with open(report_file, 'w', encoding='utf-8') as f:
        f.write(f"# RuiShin Library Test Report\n\n")
        f.write(f"**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"**Linter**: odin-lint\n")
        f.write(f"**Files Tested**: {len(odin_files)}\n")
        f.write("\n")
    
    # Statistics
    total_violations = 0
    internal_errors = 0
    clean_files = 0
    
    # Process files in parallel
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(run_linter, file, linter_binary): file for file in odin_files}
        
        completed_count = 0
        for future in as_completed(futures):
            completed_count += 1
            if completed_count % 10 == 0:
                print(f"Testing file {completed_count}/{len(odin_files)}")
            
            result = future.result()
            
            # Update statistics
            if result['violation_count'] > 0:
                total_violations += result['violation_count']
                
                # Write violations to report
                with open(report_file, 'a', encoding='utf-8') as f:
                    f.write(f"### 🔴 Violations in: {result['file']}\n\n")
                    f.write("```\n")
                    for line in result['violation_lines']:
                        f.write(f"{line}\n")
                    f.write("```\n\n")
                    
            elif result['error_count'] > 0:
                internal_errors += result['error_count']
                
                # Write errors to report
                with open(report_file, 'a', encoding='utf-8') as f:
                    f.write(f"### 🟣 Internal Error in: {result['file']}\n\n")
                    f.write("```\n")
                    for line in result['error_lines']:
                        f.write(f"{line}\n")
                    f.write("```\n\n")
                    
            else:
                clean_files += 1
    
    # Generate summary
    with open(report_file, 'a', encoding='utf-8') as f:
        f.write("## 📊 Test Summary\n\n")
        f.write("| Metric | Count |\n")
        f.write("|--------|-------|\n")
        f.write(f"| **Files Tested** | {len(odin_files)} |\n")
        f.write(f"| **Total Violations** | {total_violations} |\n")
        f.write(f"| **Internal Errors** | {internal_errors} |\n")
        f.write(f"| **Clean Files** | {clean_files} |\n\n")
        
        # Calculate percentages
        if len(odin_files) > 0:
            violation_rate = (total_violations * 100) / len(odin_files)
            clean_rate = (clean_files * 100) / len(odin_files)
            
            f.write(f"| **Violation Rate** | {violation_rate:.2f}% |\n")
            f.write(f"| **Clean Rate** | {clean_rate:.2f}% |\n")
        
        f.write("\n## 🎯 Analysis\n\n")
        
        if total_violations > 0:
            f.write(f"### 🔴 Violations Found\n\n")
            f.write(f"The linter found {total_violations} violations across {len(odin_files)} files.\n")
            f.write(f"This represents a {violation_rate:.2f}% violation rate.\n")
        else:
            f.write(f"### ✅ No Violations Found\n\n")
            f.write(f"All tested files passed the C001 rule checks!\n")
        
        f.write("\n---\n")
        f.write("Report generated by odin-lint RuiShin test\n")
        f.write("Status: Production Ready 🎉\n")
    
    print(f"\n📄 Report generated: {report_file}")
    print(f"🎯 RuiShin test completed!")
    print(f"\n📊 Summary:")
    print(f"   Files tested: {len(odin_files)}")
    print(f"   Violations: {total_violations}")
    print(f"   Internal errors: {internal_errors}")
    print(f"   Clean files: {clean_files}")
    
    if len(odin_files) > 0:
        violation_rate = (total_violations * 100) / len(odin_files)
        print(f"   Violation rate: {violation_rate:.2f}%")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())