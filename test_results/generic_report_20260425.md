
# Comprehensive Odin Lint Test Report

**Generated**: 2026-04-25 10:00:58
**Files Tested**: 271
**Files with Violations**: 25

## 📊 Summary

### 🔴 C001 Violations (Memory Safety)
**Total**: 67
**Files Affected**: 25

### 🟣 C002 Violations (Pointer Safety)
**Total**: 0
**Files Affected**: 0

### 🟥 Internal Errors
**Total**: 0

## 📝 Detailed Results

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tools/odin/diagnose_svg_rsd.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tools/odin/diagnose_svg_rsd.odin:46:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/renderer/test_advanced_features.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/renderer/test_advanced_features.odin:34:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/renderer/test_advanced_features.odin:49:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/renderer/test_advanced_features.odin:193:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_perspective.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_perspective.odin:113:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_animation.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_animation.odin:82:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_animation.odin:87:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_animation.odin:108:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:16:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:20:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:52:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:57:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:90:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:92:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:105:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:184:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_path_gradients.odin:188:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_scene_graph.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_scene_graph.odin:232:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_hit_testing.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_hit_testing.odin:77:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_simple_scene.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_simple_scene.odin:151:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_scene_graph_realistic.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_scene_graph_realistic.odin:190:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_image_handling.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_image_handling.odin:21:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_image_handling.odin:71:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_image_handling.odin:104:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_image_handling.odin:153:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_image_handling.odin:190:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_image_handling.odin:228:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_input_system.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_input_system.odin:184:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/engine/test_input_system.odin:233:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_phase10d_performance.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_phase10d_performance.odin:93:9: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:22:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:75:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:87:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:131:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:190:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/vendor-local/clay/bindings/odin/examples/clay-official-website/clay-official-website.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/vendor-local/clay/bindings/odin/examples/clay-official-website/clay-official-website.odin:466:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:120:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:141:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:145:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:223:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:248:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:329:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:348:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:351:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_text.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_text.odin:102:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_text.odin:319:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/gpu_asset_manager.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/gpu_asset_manager.odin:98:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_render.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_render.odin:120:9: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:4360:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:5968:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:5979:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:6015:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:6163:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:870:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1050:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1306:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1310:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1324:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1325:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1408:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_parser.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_parser.odin:505:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/font_manager.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/font_manager.odin:170:3: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:198:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:324:8: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:330:8: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/assets/manager.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/assets/manager.odin:89:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/assets/colors.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/assets/colors.odin:84:2: C001 [correctness] Allocation without matching defer free in same scope


## 🎯 Analysis

### ✅ Success Rate
**Clean Files**: 246 (90.8%)
**Violation Rate**: 9.2%

### 📊 Rule Effectiveness
- C001 (Memory Safety): 67 violations
- C002 (Pointer Safety): 0 violations
- Total violations: 67

## 🎉 Conclusion

Status: Production Ready 🚀
    