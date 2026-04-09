
# Comprehensive Odin Lint Test Report

**Generated**: 2026-04-06 14:18:09
**Files Tested**: 262
**Files with Violations**: 41

## 📊 Summary

### 🔴 C001 Violations (Memory Safety)
**Total**: 121
**Files Affected**: 39

### 🟣 C002 Violations (Pointer Safety)
**Total**: 2
**Files Affected**: 2

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

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_stencil_functionality.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_stencil_functionality.odin:25:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/unit/graphics/test_stencil_functionality.odin:26:2: C001 [correctness] Allocation without matching defer free in same scope

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

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/rsd/rsd_test.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/rsd/rsd_test.odin:183:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_critical_paths.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_critical_paths.odin:79:9: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_critical_paths.odin:88:9: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_critical_paths.odin:97:9: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_critical_paths.odin:179:9: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_phase10d_performance.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/performance/test_phase10d_performance.odin:93:9: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:22:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:75:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:87:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:131:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/2d/test_svg_gradient.odin:190:2: C001 [correctness] Allocation without matching defer free in same scope

### 🟣 C002 Violations in: /Users/rainer/Development/MyODIN/RuiShin/tests/stress/test_simple_stress.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/tests/stress/test_simple_stress.odin:52:3: C002 [correctness] Multiple defer frees on same allocation

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/vendor-local/odin-freetype/demo/demo.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/vendor-local/odin-freetype/demo/demo.odin:79:4: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/vendor-local/clay/bindings/odin/examples/clay-official-website/clay-official-website.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/vendor-local/clay/bindings/odin/examples/clay-official-website/clay-official-website.odin:466:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/main.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/main.odin:719:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/main.odin:739:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/main.odin:794:3: C001 [correctness] Allocation without matching defer free in same scope

### 🟣 C002 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/parser.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/parser.odin:763:6: C002 [correctness] Multiple defer frees on same allocation

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:120:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:141:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:145:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:223:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:248:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:329:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:348:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/ui/theme/accessibility.odin:351:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/renderer/draw_list.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/renderer/draw_list.odin:698:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/renderer/error_handling.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/renderer/error_handling.odin:37:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/renderer/error_handling.odin:38:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/renderer/error_handling.odin:44:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/layout/layout.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/layout/layout.odin:87:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/layout/layout.odin:90:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/layout/layout.odin:91:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_render.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_render.odin:220:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_render.odin:221:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_render.odin:260:4: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_render.odin:261:4: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_text.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_text.odin:102:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_text.odin:319:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_text.odin:556:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/animation.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/animation.odin:105:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/animation.odin:295:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/animation.odin:442:5: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/gpu_asset_manager.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/gpu_asset_manager.odin:98:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_render.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_render.odin:120:9: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:870:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1050:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1306:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1310:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1324:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1325:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_draw.odin:1408:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_decoder.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_decoder.odin:124:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_decoder.odin:327:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/rsd_decoder.odin:382:4: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/font_manager.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/font_manager.odin:102:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/font_manager.odin:103:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/font_manager.odin:112:3: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/font_manager.odin:170:3: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_parser.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_parser.odin:309:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_parser.odin:373:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_parser.odin:503:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/svg_parser.odin:1375:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:1288:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:1350:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:4258:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:5857:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:5868:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:5904:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/g2d_core.odin:6036:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:100:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:101:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:120:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:121:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:122:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:331:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:343:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:344:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/bidi.odin:345:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/itemize.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/itemize.odin:20:3: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:106:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:112:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:198:5: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:324:8: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:330:8: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:395:2: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/layout.odin:396:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/shaper.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/shaper.odin:43:11: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/shaper.odin:45:11: C001 [correctness] Allocation without matching defer free in same scope
🔴 /Users/rainer/Development/MyODIN/RuiShin/src/graphics/text/shaper.odin:299:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/assets/manager.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/assets/manager.odin:89:2: C001 [correctness] Allocation without matching defer free in same scope

### 🔴 C001 Violations in: /Users/rainer/Development/MyODIN/RuiShin/src/assets/colors.odin

🔴 /Users/rainer/Development/MyODIN/RuiShin/src/assets/colors.odin:84:2: C001 [correctness] Allocation without matching defer free in same scope


## 🎯 Analysis

### ✅ Success Rate
**Clean Files**: 221 (84.4%)
**Violation Rate**: 15.6%

### 📊 Rule Effectiveness
- C001 (Memory Safety): 121 violations
- C002 (Pointer Safety): 2 violations
- Total violations: 123

## 🎉 Conclusion

Status: Production Ready 🚀
    