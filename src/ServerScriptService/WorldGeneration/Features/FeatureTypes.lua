--!strict

export type Bounds = {
	min: Vector3,
	max: Vector3,
}

export type BoxSpec = {
	id: string,
	bounds: Bounds,
	material: Enum.Material,
	color: Color3,
	transparency: number,
	canCollide: boolean,
	canQuery: boolean,
	canTouch: boolean,
	castShadow: boolean,
	role: string,
	sectionId: string,
}

export type SurfaceRegion = {
	id: string,
	role: string,
	bounds: Bounds,
	sectionId: string?,
}

export type FeatureSection = {
	id: string,
	bounds: Bounds,
}

export type FeaturePlan = {
	id: string,
	kind: string,
	version: number,
	seed: number,
	bounds: Bounds,
	sections: { FeatureSection }?,
	parts: { BoxSpec },
	carveVolumes: { Bounds },
	surfaceRegions: { SurfaceRegion },
	exclusions: { Bounds },
	stats: { [string]: number },
}

return table.freeze({
	Kinds = table.freeze({
		PillarCluster = "PillarCluster",
		Ravine = "Ravine",
	}),
})
