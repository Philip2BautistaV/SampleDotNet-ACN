var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Happy Birthday my Lovely Wife Khrisca");

app.Run();
