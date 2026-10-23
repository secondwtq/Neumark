// bullet_bench.cpp - headless Bullet3 benchmark harness.
//
// Runs one of the App_Benchmarks scenes (BenchmarkDemo, from
// examples/Benchmarks) without any graphics: fixed timestep physics
// stepping for a fixed number of frames.  Deterministic (same scene
// construction, same dt) apart from solver nondeterminism at run-to-run
// level, which is inherent to the physics engine.
//
// Usage: bullet_bench <benchmark 1-8> <frames>

#include "CommonInterfaces/CommonExampleInterface.h"
#include "CommonInterfaces/CommonGUIHelperInterface.h"
#include "CommonInterfaces/CommonParameterInterface.h"
#include "Benchmarks/BenchmarkDemo.h"

#include <cstdio>
#include <cstdlib>

// CommonRigidBodyMTBase::createDefaultParameters registers UI parameters;
// with a graphics-less helper we must supply a stub parameter interface.
struct StubParameterInterface : CommonParameterInterface
{
	void registerSliderFloatParameter(SliderParams&) {}
	void registerButtonParameter(ButtonParams&) {}
	void registerComboBox(ComboBoxParams&) {}
	void syncParameters() {}
	void removeAllParameters() {}
	void setSliderValue(int, double) {}
};

struct BenchGUIHelper : DummyGUIHelper
{
	StubParameterInterface m_params;
	CommonParameterInterface* getParameterInterface() { return &m_params; }
};

int main(int argc, char** argv)
{
	int bench = argc > 1 ? atoi(argv[1]) : 1;
	int frames = argc > 2 ? atoi(argv[2]) : 3600;
	const char* benchName = "unknown";
	switch (bench)
	{
		case 1: benchName = "3000 boxes"; break;
		case 2: benchName = "1000 stack"; break;
		case 3: benchName = "Ragdolls"; break;
		case 4: benchName = "Convex stack"; break;
		case 5: benchName = "Prim vs Mesh"; break;
		case 6: benchName = "Convex vs Mesh"; break;
		case 7: benchName = "Raycast"; break;
		case 8: benchName = "Raycast (2)"; break;
		default: break;
	}

	{
		BenchGUIHelper noGfx;
		CommonExampleOptions options(&noGfx);
		options.m_option = bench;  // selects the benchmark scene (1-8)
		CommonExampleInterface* demo = BenchmarkCreateFunc(options);
		demo->initPhysics();
		for (int i = 0; i < frames; i++)
		{
			demo->stepSimulation(1.0f / 60.0f);
		}
		demo->exitPhysics();
		delete demo;
	}

	printf("bullet_bench done: benchmark %d (%s), %d frames\n", bench, benchName, frames);
	return 0;
}
