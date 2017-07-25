//
//  shaders.metal
//  macos_swift_metal_webcam_filter
//
//  Created by Hoàng Xuân Quang on 7/26/17.
//  Copyright © 2017 Hoang Xuan Quang. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 renderedCoordinate [[position]];
    float2 textureCoordinate;
} TextureMappingVertex;

// Rec 709 LUMA values for grayscale image conversion
constant float3 kRec709Luma = float3(0.2126, 0.7152, 0.0722);

vertex TextureMappingVertex mapTexture(unsigned int vertex_id [[ vertex_id ]]) {
    float4x4 renderedCoordinates = float4x4(float4( -1.0, -1.0, 0.0, 1.0 ),
                                            float4(  1.0, -1.0, 0.0, 1.0 ),
                                            float4( -1.0,  1.0, 0.0, 1.0 ),
                                            float4(  1.0,  1.0, 0.0, 1.0 ));

    float4x2 textureCoordinates = float4x2(float2( 0.0, 1.0 ),
                                           float2( 1.0, 1.0 ),
                                           float2( 0.0, 0.0 ),
                                           float2( 1.0, 0.0 ));
    TextureMappingVertex outVertex;
    outVertex.renderedCoordinate = renderedCoordinates[vertex_id];
    outVertex.textureCoordinate = textureCoordinates[vertex_id];

    return outVertex;
}

fragment float4 displayTexture(TextureMappingVertex mappingVertex [[ stage_in ]],
                               texture2d<float, access::sample> texture [[ texture(0) ]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 inColor = float4(texture.sample(s, mappingVertex.textureCoordinate));
    float gray = dot(inColor.rgb, kRec709Luma);
    float4 outColor = float4(gray,gray,gray,1.0);
    return outColor;
}
