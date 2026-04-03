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
    ols_root = "./vendor/ols"
    output_dir = "test_results"
    linter_binary = "./artifacts/odin-lint"
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate report filenames
    summary_file = os.path.join(output_dir, f"ols_focused_analysis_{datetime.now().strftime('%Y%m%d')}.txt")
    detailed_file = os.path.join(output_dir, f"ols_focused_detailed_{datetime.now().strftime('%Y%m%d')}.txt")
    
    print("=== FOCUSED OLS CODEBASE ANALYSIS ===")
    print("Testing C001 rule on Odin files in vendor/ols/src/")
    print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Find all Odin files in vendor/ols/src
    odin_files = []
    src_dir = os.path.join(ols_root, "src")
    
    if os.path.isdir(src_dir):
        for root, dirs, files in os.walk(src_dir):
            for file in files:
                if file.endswith('.odin'):
                    odin_files.append(os.path.join(root, file))
    
    if not odin_files:
        print("❌ No Odin files found in OLS source directory")
        return 1
    
    print(f"🔍 Testing {len(odin_files)} OLS source files...")
    
    # Initialize counters
    files_with_violations = 0
    files_without_violations = 0
    total_violations = 0
    internal_errors = 0
    
    # Initialize output files
    with open(summary_file, 'w', encoding='utf-8') as f:
        f.write("=== Focused OLS Codebase Analysis Report ===\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("Linter: odin-lint\n")
        f.write("Rule: C001 (Allocation without defer free)\n")
        f.write("Directory: vendor/ols/src/\n")
        f.write("\n")
    
    # Process files in parallel
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(run_linter, file, linter_binary): file for file in odin_files}
        
        completed_count = 0
        for future in as_completed(futures):
            completed_count += 1
            if completed_count % 10 == 0:
                print(f"  Processed {completed_count}/{len(odin_files)} files")
            
            result = future.result()
            
            # Write detailed report
            with open(detailed_file, 'a', encoding='utf-8') as f:
                f.write(f"=== Analysis for: {result['file']} ===\n")
                f.write(f"Violations: {result['violation_count']}\n")
                f.write(f"Errors: {result['error_count']}\n")
                f.write("\n")
                
                if result['violation_count'] > 0:
                    f.write("C001 Violations:\n")
                    for line in result['violation_lines']:
                        f.write(f"  {line}\n")
                    f.write("\n")
                
                if result['error_count'] > 0:
                    f.write("Errors:\n")
                    for line in result['error_lines']:
                        f.write(f"  {line}\n")
                    f.write("\n")
                
                f.write("-" * 50 + "\n\n")
            
            # Update counters
            if result['violation_count'] > 0:
                files_with_violations += 1
                total_violations += result['violation_count']
                print(f"❌ C001 violations in: {result['file']}")
                
                # Add to summary
                with open(summary_file, 'a', encoding='utf-8') as f:
                    f.write(f"{result['file']}\n")
                    
            elif result['error_count'] > 0:
                internal_errors += result['error_count']
                print(f"⚠️  Internal errors in: {result['file']}")
                
            else:
                files_without_violations += 1
    
    # Generate final summary
    with open(summary_file, 'a', encoding='utf-8') as f:
        f.write("\n" + "=" * 50 + "\n")
        f.write("SUMMARY\n")
        f.write("=" * 50 + "\n")
        f.write(f"Total files analyzed: {len(odin_files)}\n")
        f.write(f"Files with violations: {files_with_violations}\n")
        f.write(f"Files without violations: {files_without_violations}\n")
        f.write(f"Total C001 violations: {total_violations}\n")
        f.write(f"Internal errors: {internal_errors}\n")
        
        if len(odin_files) > 0:
            violation_rate = (files_with_violations * 100) / len(odin_files)
            f.write(f"Violation rate: {violation_rate:.2f}%\n")
    
    print(f"\n📊 OLS Analysis Complete!")
    print(f"   Files analyzed: {len(odin_files)}")
    print(f"   Files with violations: {files_with_violations}")
    print(f"   Files without violations: {files_without_violations}")
    print(f"   Total C001 violations: {total_violations}")
    print(f"   Internal errors: {internal_errors}")
    
    if len(odin_files) > 0:
        violation_rate = (files_with_violations * 100) / len(odin_files)
        print(f"   Violation rate: {violation_rate:.2f}%")
    
    print(f"\n📄 Reports generated:")
    print(f"   Summary: {summary_file}")
    print(f"   Detailed: {detailed_file}")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())