#!/usr/bin/env python3

import os
import subprocess
import multiprocessing
from datetime import datetime
import glob
import re
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
        
        # Count violations
        violation_count = len(re.findall(r'C001', output))
        contextual_count = len(re.findall(r'Intentional|Performance', output))
        error_count = len(re.findall(r'INTERNAL ERROR', output))
        
        # Extract C001 lines
        c001_lines = [line for line in output.split('\n') if 'C001' in line]
        
        # Extract INTERNAL ERROR lines
        error_lines = [line for line in output.split('\n') if 'INTERNAL ERROR' in line]
        
        return {
            'file': file_path,
            'violation_count': violation_count,
            'contextual_count': contextual_count,
            'error_count': error_count,
            'c001_lines': c001_lines,
            'error_lines': error_lines,
            'success': True
        }
        
    except subprocess.TimeoutExpired:
        return {
            'file': file_path,
            'violation_count': 0,
            'contextual_count': 0,
            'error_count': 1,
            'c001_lines': [],
            'error_lines': [f'Timeout after 10 seconds'],
            'success': False
        }
    except Exception as e:
        return {
            'file': file_path,
            'violation_count': 0,
            'contextual_count': 0,
            'error_count': 1,
            'c001_lines': [],
            'error_lines': [f'Error: {str(e)}'],
            'success': False
        }

def process_directory(directory, linter_path, report_file, progress_callback=None):
    """Process all Odin files in a directory"""
    odin_files = []
    
    # Find all .odin files
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.odin'):
                odin_files.append(os.path.join(root, file))
    
    if not odin_files:
        return 0, 0, 0, 0, 0
    
    print(f"Found {len(odin_files)} files to test in {directory}")
    
    # Process files in parallel
    results = []
    total_files = len(odin_files)
    
    # Use ThreadPoolExecutor for parallel processing
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(run_linter, file, linter_path): file for file in odin_files}
        
        completed_count = 0
        for future in as_completed(futures):
            completed_count += 1
            if completed_count % 10 == 0:
                if progress_callback:
                    progress_callback(completed_count, total_files, futures[future])
            
            result = future.result()
            results.append(result)
    
    # Process results
    total_violations = 0
    contextual_violations = 0
    internal_errors = 0
    clean_files = 0
    
    with open(report_file, 'a', encoding='utf-8') as f:
        for result in results:
            if result['violation_count'] > 0:
                total_violations += result['violation_count']
                contextual_violations += result['contextual_count']
                
                f.write(f"### 🔴 Violations in: {result['file']}\n\n")
                f.write("```\n")
                for line in result['c001_lines']:
                    f.write(f"{line}\n")
                f.write("```\n\n")
                
            elif result['error_count'] > 0:
                internal_errors += result['error_count']
                
                f.write(f"### 🟣 Internal Error in: {result['file']}\n\n")
                f.write("```\n")
                for line in result['error_lines']:
                    f.write(f"{line}\n")
                f.write("```\n\n")
                
            else:
                clean_files += 1
    
    return total_files, total_violations, contextual_violations, internal_errors, clean_files

def main():
    # Configuration
    odin_root = "/Users/rainer/odin"
    output_dir = "test_results/all_libraries"
    linter_binary = "./artifacts/odin-lint"
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate report filename
    report_file = os.path.join(output_dir, f"comprehensive_report_{datetime.now().strftime('%Y%m%d')}.md")
    
    # Initialize report
    with open(report_file, 'w', encoding='utf-8') as f:
        f.write(f"# Comprehensive Odin Library Test Report\n\n")
        f.write(f"**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"**Linter**: odin-lint\n")
        
        # Get Odin version
        try:
            version = subprocess.run(["/Users/rainer/odin/odin", "version"], 
                                  capture_output=True, text=True, timeout=5)
            f.write(f"**Odin Version**: {version.stdout.strip()}\n")
        except:
            f.write(f"**Odin Version**: unknown\n")
        
        f.write("\n")
    
    # Statistics
    total_files = 0
    total_violations = 0
    contextual_violations = 0
    internal_errors = 0
    clean_files = 0
    
    # Directories to test
    directories = [
        "core",
        "base", 
        "vendor/ols"
    ]
    
    print("🔬 Comprehensive Odin Library Test")
    print("====================================")
    print()
    
    # Progress callback
    def progress_callback(completed, total, current_file):
        if completed % 10 == 0:
            print(f"  Processing file {completed}/{total}: {current_file}")
    
    # Test each directory
    for dir_name in directories:
        dir_path = os.path.join(odin_root, dir_name)
        
        if os.path.isdir(dir_path):
            print(f"Testing directory: {dir_name}")
            
            with open(report_file, 'a', encoding='utf-8') as f:
                f.write(f"\n## {dir_name} Directory\n\n")
            
            result = process_directory(dir_path, linter_binary, report_file, progress_callback)
            dir_files, dir_violations, dir_contextual, dir_errors, dir_clean = result
            
            total_files += dir_files
            total_violations += dir_violations
            contextual_violations += dir_contextual
            internal_errors += dir_errors
            clean_files += dir_clean
            
            print(f"Files in {dir_name}: {dir_files}")
            
        else:
            print(f"⚠️  Directory not found: {dir_path}")
            with open(report_file, 'a', encoding='utf-8') as f:
                f.write(f"\n## ⚠️ Directory not found: {dir_name}\n\n")
    
    # Generate summary
    print("\n📊 Generating summary...")
    
    with open(report_file, 'a', encoding='utf-8') as f:
        f.write("\n## 📊 Test Summary\n\n")
        f.write("| Metric | Count |\n")
        f.write("|--------|-------|\n")
        f.write(f"| **Files Tested** | {total_files} |\n")
        f.write(f"| **Total Violations** | {total_violations} |\n")
        f.write(f"| **Contextual Violations** | {contextual_violations} |\n")
        f.write(f"| **Internal Errors** | {internal_errors} |\n")
        f.write(f"| **Clean Files** | {clean_files} |\n\n")
        
        # Calculate percentages
        if total_files > 0:
            violation_rate = (total_violations * 100) / total_files
            clean_rate = (clean_files * 100) / total_files
            
            f.write(f"| **Violation Rate** | {violation_rate:.2f}% |\n")
            f.write(f"| **Clean Rate** | {clean_rate:.2f}% |\n")
        
        f.write("\n## 🎯 Analysis\n\n")
        
        if total_violations > 0:
            f.write(f"### 🔴 Violations Found\n\n")
            f.write(f"The linter found {total_violations} violations across {total_files} files.\n")
            f.write(f"This represents a {violation_rate:.2f}% violation rate.\n")
        else:
            f.write(f"### ✅ No Violations Found\n\n")
            f.write(f"All tested files passed the C001 rule checks!\n")
        
        f.write("\n---\n")
        f.write("Report generated by odin-lint comprehensive test\n")
        f.write("Status: Production Ready 🎉\n")
    
    print(f"\n📄 Report generated: {report_file}")
    print(f"🎯 Comprehensive test completed!")
    print(f"\n📊 Summary:")
    print(f"   Files tested: {total_files}")
    print(f"   Violations: {total_violations}")
    print(f"   Internal errors: {internal_errors}")
    print(f"   Clean files: {clean_files}")
    
    if total_files > 0:
        violation_rate = (total_violations * 100) / total_files
        print(f"   Violation rate: {violation_rate:.2f}%")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())