=== clibs/terrain ����ģ�� ===

    terrain.lua            �����û��� LUA API 
    terrain.cpp           c dll�ṩ���ټ���,ֻ�� terrain.lua ʹ�ã����ϲ��û����� 

    terrain.lua            lua layer API 
    terrain.cpp           c layer API 

--- util_* ��������----
    utilclass.lua          �ֵ����ģ�� LUA ����
    utilmath.lua         ���� direction ����ѧ����
    utiltexture.lua      ������غ���(��ant framework �ϲ�ʱ��ɾ����

---  ���Գ����ļ� ---
test_*.lua 
    test_class.lua        lua class usage 
    test_lterrain.lua    lterrain.dll usage
    test_tex.lua          texload usage 

	
=== ��Դ�ļ� === 

--- ���ιؿ��ļ� ---
pvp.lvl 
    terrain level config sample 

--- ���������ļ�Ŀ¼ ---
    terrain resource directory: /Work/ant/assets/build/terrain

-- shader �ļ�Ŀ¼ ----
    terrain shader source directory: /Work/ant/assets/shaders/src/terrain

--- ����ת����ʽ ------
base and mask images  must convert to dds
     base  with mipmap format = bc3 
     mask  without mipmap

	 
	 
	 
�ϲ����룺
    ���� terrain.cpp �� clibs/bgfx
    �޸� bgfx �µ�makefile ���� terrain.cpp
    �޸� terrain.cpp �ļ�������ӿ�,
        luaopen_lterrain ��Ϊ luaopen_bgfx_terrain
    ��Ϊbgfx���̵�һ����ģ����� 
    lua layer terrain api ����ʱ��ʹ�� require "bgfx.terrain"

	
	