#### 架构
1. RT需要使用FrameGraph的形式进行修改。目前postprocess尤其需要这个修改进行不同pass的引用；
2. 使用DeferredShading。目前的one pass deferred能够很好解决deferrd shading占用过多带宽的问题；

#### Bug
##### 已经完成
1. 修复引擎在D3D12/Vulkan中的问题；
2. 修复bloom后处理，在emissive color值很高的时候，依然没有bloom的效果。具体使用furnace-1.glb这个文件用于测试；(2022.11.08已经完成)
3. 将render_layer也bgfx.submit中的depth关联起来，并将viewmode改成与depth相关的设定；(2023.02.06已经完成)

##### 未完成
1. 修复shader下的cubemap resource，绑定为texture2d array的问题。具体重现的方法是，在iOS开发环境下，打开对应的shader validation等相关的debug选项就会有相应的报错；
2. 修复Vulkan下，使用spirv16-13方式编译着色器后，打开bgfx的debuglog，会在renderer_vk中的debugReportCb函数里面报错。目前使用spirv编译vulkan的着色器；
3. 目前高光在features的例子里面会爆掉，高光会变成纯白色；
4. 调整iOS和Android下的ASTC压缩格式。目前强制使用了ASTC4x4，因为之前bgfx不支持ASTC6x6，最近更新了，看看是否ASTC的格式都支持全了（2023.4.21。经过测试，能够通过texturec工具把纹理压缩成ASTC6x6，但纹理会出现错误，目前需要查一下是什么问题）；

#### 编辑器相关
1. 优化材质编辑器

#### 优化
##### 已经完成
1. 顶点相关：
  - 顶点压缩。
    1) 使用四元数多normal/tangent/bitangent进行压缩；(2022.11.08已经完成)
    2) 使用更多的16bit的顶点数据，以更大程度上压缩顶点占用的数量；
  - 顶点数据使用不同的流。目前所有顶点都打包到一个流里面，当某个着色器不会访问到对应的顶点数据的时候，相应的带宽就会被浪费掉了。但目前代码很多地方都依赖着只有一个流的逻辑，多个流的情况是否真的能够提交性能还需要验证；
2. 后处理
  1) Bloom目前的效果并不好；(2022.11.08已经完成)
3. 使用FXAA/TAA，解决bgfx在MSAA下，不同平台直接很多bug的问题。(2022.11.08已经完成)
4. 使用compute shader将MSAA的深度resolve到普通的深度；(2022.11.08已经完成。但不同的机器resolve msaa的depth硬件不一定支持)
5. 增强阴影的效果，包括精度和和filter的阴影，或对比使用PCF的效果；(2022.11.08已经完成)
6. 着色器优化。尽可能使用mediump和lowp格式。目前默认全部都是highp格式；（2022.12.31已经完成）
7. 转换到Vulkan（全平台支持，Mac和iOS使用MoltenVK）。（2023.1.10已经完成）
8. 清理引擎中的varying.def.sc文件。引擎内，应该只使用一个varying的文件定义，不应该过度的随意添加。后续需要针对VS_Output与FS_Input进行关联；
9. 优化动画计算，将skinning的代码从vertex shader放到compute shader中，并消除shadow/pre-depth/main pass中分别重复的计算（https://wickedengine.net/2017/09/09/skinning-in-compute-shader/）。（2023.04.21.这种方法有一个问题，会导致所有的顶点、法线需要复制一份出来作为中间数据，不管顶点数据是否是共用的，每一个实例都需要一份。这会导致D3D11在创建大量entity后报错，目前使用vs中的skinning计算方法）；
10. Outline问题的修复。目前使用放大模型的方式实现描边的效果，但会有被遮挡的问题。要不使用屏幕空间算法，要不调整放大模型的渲染，防止被遮挡。https://zhuanlan.zhihu.com/p/410710318；https://zhuanlan.zhihu.com/p/109101851；https://juejin.cn/post/7163670845343137800；目前继续使用沿法线放大模型的方式，结合模板的方式，实现。(2023.05.26)；
11. 关于ibl：
  - 使用sh(Spherical Harmonic)来表示irradiance中的数据；
  - 使用多项式直接计算LUT，而不使用一张额外的贴图（节省带宽和采样器）：https://knarkowicz.wordpress.com/2014/12/27/analytical-dfg-term-for-ibl/；（2023.06.27已经完成）
12. 使用无穷远的far plane构建透视投影矩阵，并将near plane的位置设定为0.1，而不是现在1，1的距离有时候会导致近处能够看到的物体，但被裁剪掉的问题；(2023.06已经完成，目前在camera component上会保存: infviewprojmat和viewprojmat)；
13. 修改贴图的mipmap颜色为某种纯色，用来检测场景中的贴图是否过大（看到蓝色意味着原来做的图就是过大的）；（2023.10已经完成，debug_mipmap_system）

##### 未完成
1. 优化PBR的计算量：
  - 预烘培GGX：http://filmicworlds.com/blog/optimizing-ggx-shaders-with-dotlh/；
2. 关于ibl:
  - 离线计算ibl相关的数据，将目前的compute shader中计算的内容转移到cpu端，并离线计算；
3. 使用更优质的line渲染：
  - 优化目前使用的polyline的效果。尤其是不在使用MSAA，换用FXAA之后，polyline的线会丢失（https://mattdesl.svbtle.com/drawing-lines-is-hard，参考的库：https://github.com/spite/THREE.MeshLine）；
  - 需要一个更优质的网格：https://bgolus.medium.com/the-best-darn-grid-shader-yet-727f9278b9d8
4. 使用延迟渲染。目前的predepth系统、FXAA（以及将要实现的TAA）实际上是延迟渲染的一部分，实现延迟渲染能够减少目前的drawcall（目前的draw call由predepth，shadow，render和pickup 4部分组成）；
5. 修复pre-depth/csm/pickup等队列中的cullstate的状态。对于metal/vulkan/d3d12等api，pipeline都是一个整体，会导致pipeline数据不停的切换；
6. 针对Vulkan上的subpass对渲染的render进行相应的优化；
7. 后处理优化
  - 充分利用全屏/半屏的render_target，而不是每个后处理的draw都用一个新的target；
  - 后处理的DoF是时候要解决了。bgfx里面有一个one pass的DoF例子，非常值得参考；
  - Color Grading需要用于调整颜色；
  - tonemapping能够预先bake到一张贴图里面，而不需要单独在fragment阶段进行计算。具体要看filament里面的tonemapping的操作；
  - AO效果和效率的优化。效果：修复bent_normal和cone tracing的bug；效率：使用hi-z提高深度图的采样（主要是采样更低的mipmap，提高缓存效率）；
8. 优化动画计算，将skinning的代码从vertex shader放到compute shader中，并消除shadow/pre-depth/main pass中分别重复的计算（https://wickedengine.net/2017/09/09/skinning-in-compute-shader/）；
9. 水渲染；
10. 点光源，包括point、spot和rectangle/plane的区域光，包括其对应的阴影；
11. 对相同材质的物体进行排序渲染，目前渲染顺序的提交，都是按照提交的先后次序来的。还需要单独对alpha test的物体进行分类（分类的队列顺序应该为：opaque->alpha test-> translucent）。而对于translucent的物体来讲，还需要根据从远到近的排序来渲染（避免alpha blend错误）；
12. 考虑一下把所有的光照计算都放在view space下面进行计算。带来的好处是，u_eyePos/v_distanceVS/v_posWS这些数据都不需要占用varying，都能够通过gl_FragCoord反算回来（某些算法一定需要做这种计算）；
13. 渲染遍历在场景没有任何变化的时候，直接用上一帧的数据进行提交，而不是现在每一帧都在遍历；
14. 优化bgfx的draw viewid和compute shader viewid；
15. 在方向光的基础上，定义太阳光。目前方向光是只有方向，没有大小和位置，而太阳实际上是有位置和大小的；
16. 摄像机的fov需要根据聚焦的距离来定义fov；
17. 合拼UI上使用的贴图（主要是Rmlui，用altas的方法把贴图都拼到一张大图里面）。目前的想法是，1.接管UI的集合体生成方式，UV的信息有UI的管理器去生成；2.做一个类似于虚拟贴图的东西，把每个UI上面的UV映射放到一个buffer里面，运行时在vs里面取对应的uv；
18. 增加开关，用于控制场景是否继续渲染，并把前一刻的画面存下来进行模糊，用于在操作UI的时候，停止场景渲染用的；
19. 优化HDR的贴图使用。例如ColorGrading中的RGBA32F应该使用R10G10B10A2的格式，HDR的环境贴图等；
20. 解决动态材质的问题；
  - 需要把vs_pbr.sc里面的VS_Input和VS_Ouput拆分出来。目前已经定义好了，还需要后续的跟进；
  - 重新思考动态材质的实现。需要从模型->顶点着色器输入->像素着色器输入的链条思考如何有效、简单便捷和兼顾一致性的情况定义材质；
21. 顶点着色器与vb绑定的时候，需要确保顶点着色器需要的数据，vb的layout上面是有所提供的；

##### 暂缓进行
1. 确认一下occlusion query是否在bgfx中被激活，参考https://developer.download.nvidia.cn/books/HTML/gpugems/gpugems_ch29.html，实现相应的遮挡剔除；
2. 使用draw indirect的时候，在cull的阶段，获取一个粗糙的z-buffer（可以在cpu端生成http://twvideo01.ubm-us.net/o1/vault/gdcchina14/presentations/833779_MiloYip_ADataOrientedCN.pdf，也可以在gpu端生成），用以判断这个物体就算在视锥体内，也是可以被剔除的；
3. 使用Hi-Z的方式进行剔除；

##### 已知问题但不修复
1. 充分理解ASTC压缩，修复6x6的贴图无法正确压缩的bug。https://registry.khronos.org/DataFormat/specs/1.3/dataformat.1.3.html#ASTC https://github.com/ARM-software/astc-encoder/blob/main/Docs/FormatOverview.md；（不修复原因：目前使用的纹理工具是bgfx内的texturec工具，texturec工具内部对于ASTC这种异形format的支持都是有问题的，具体看提过的issue和pr就知道）；

#### 新功能/探索
##### 已经完成
1. 阴影的VSM；  //2022.09.29已经完成，使用的是ESM。
2. 天气系统。让目前游戏能够昼夜变化。一个简单的方式是使用后处理的color grading改变色调，另外一个更正确的方法是使用预烘培的大气散射模拟天空，将indirect lighting和天空和合拼；（2023.02.22已经暂停，对于移动设备并不友好）（2023.05.26目前使用的方法是，动态调整平行光的方向、intensity以及环境光的intensity来实现昼夜变化（intensity都是通过读取美术给的图来实现的）。由于基于物理的与烘培的大气散射还有很多的理论知识没有搞清楚，暂时停下来了）；

##### 未完成
1. FSR。详细看bgfx里面的fsr例子；
2. SDF Shadow；
3. Visibility Buffer；
4. GI相关。SSGI、SSR、SDFGI(https://zhuanlan.zhihu.com/p/404520592)、DDGI(Dynamic Diffuse Global Illumination，https://morgan3d.github.io/articles/2019-04-01-ddgi/)等；
5. LOD；
6. 延迟渲染。延迟渲染能够降低为大量动态光源的计算。但移动设备需要one pass deferred的支持。Vulkan在API层面上支持subpass的操作，能够很好地实现这个功能。唯一需要注意的是，使用了MoltenVK的iOS是否能够支持这个功能；
7. 尝试一下虚拟纹理。后面的GIProbe、点光源阴影都需要大量的纹理贴图。探索一下虚拟纹理是否解决这些问题，BGFX里面就有相关的例子；

#### 增强调试功能
1. 修复bgfx编译后的vulkan着色器无法在renderdoc进行单步调试；
2. 影子。只管的在屏幕上看到对应的shadowmap、csm frustum等；
3. 添加一个overdraw的模式，观察哪些像素是背多次渲染了。详细参考unity和虚幻上的做法；
4. bgfx支持查看每一个view下cpu/gpu时间，但在init的时候加上profile=true，还是无法取出每个view的时间；